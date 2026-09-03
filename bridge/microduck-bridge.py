#!/usr/bin/env python3
"""Relay robotd's Unix socket to TCP so a phone can reach it.

WHY THIS EXISTS. `robotd` listens on a Unix domain socket, `/run/robotd.sock`
by default. A phone cannot open a Unix socket on another machine, so either the
phone speaks SSH (a real implementation, host-key trust, key management) or a
small program on the robot's own computer moves the bytes. This is the small
program.

WHAT IT IS NOT. It is not a protocol. It does not parse robotd's vocabulary,
rewrite its parameters, or answer on its behalf: every byte a client sends
reaches robotd unchanged and every byte robotd sends reaches the client
unchanged. Two things are added and both are safety rather than semantics —
a first line that authorises the relay, and a deadman that sends a stop when a
client goes quiet.

THE DEADMAN IS THE REASON TO PREFER THIS OVER A RAW `socat`. A simulator gives
you a duck that stops when nobody is asking it to move; hardware does not. If
the phone goes down a lift, the Wi-Fi drops, or the app is killed mid-hold, the
robot is still walking. This sends `robot.stop` when no client line has arrived
for `--deadman` milliseconds, then keeps sending nothing. It is a floor, not a
guarantee: it cannot act if this process itself dies, which is why the systemd
unit restarts it and why robotd's own twist deadman stays the real backstop.

THE TOKEN IS NOT A SECURITY BOUNDARY, and saying so is part of shipping it. It
stops a television or a housemate's laptop stumbling into a robot. It does not
stop anyone who can read your Wi-Fi. Bind to the LAN, never to the world, and
do not port-forward it.

RUNS ANYWHERE PYTHON 3.9 DOES: standard library only, no pip, nothing to build.
Tested on this repo's Pi against a mock robotd, and on macOS.
"""

from __future__ import annotations

import argparse
import json
import os
import selectors
import socket
import stat
import sys
import threading
import time

VERSION = "microduck-bridge/1"
DEFAULT_SOCKET = "/run/robotd.sock"
DEFAULT_PORT = 7788
DEFAULT_DEADMAN_MS = 700
STOP_LINE = b'{"jsonrpc":"2.0","method":"robot.stop","params":{},"id":"bridge-deadman"}\n'


class Refusal(Exception):
    """Something the bridge will not do, in words a person can act on."""


def read_token(path: str) -> str:
    """The shared token, and a refusal if the file is readable by anybody else.

    A token in a world-readable file is not a token. This checks the mode
    rather than trusting the installer, because the installer is a shell script
    somebody may have edited.
    """
    try:
        mode = os.stat(path).st_mode
    except OSError as error:
        raise Refusal(f"no token file at {path}: {error.strerror}. "
                      "Run install.sh, or pass --token-file.") from error
    if mode & (stat.S_IRGRP | stat.S_IROTH | stat.S_IWGRP | stat.S_IWOTH):
        raise Refusal(f"{path} is readable or writable by other users "
                      f"(mode {oct(stat.S_IMODE(mode))}). chmod 600 it.")
    with open(path, "r", encoding="utf-8") as handle:
        token = handle.read().strip()
    if len(token) < 16:
        raise Refusal(f"the token in {path} is {len(token)} characters; "
                      "16 is the minimum this bridge accepts.")
    return token


def hello_is_valid(line: bytes, token: str) -> bool:
    """The first line a client sends: a version and the token, nothing else.

    Compared in constant time, which costs nothing here and means the failure
    mode is "wrong token" rather than "wrong token, and how wrong".
    """
    try:
        hello = json.loads(line.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return False
    if not isinstance(hello, dict):
        return False
    if hello.get("microduck") != "v1":
        return False
    given = hello.get("token")
    if not isinstance(given, str):
        return False
    import hmac
    return hmac.compare_digest(given, token)


class Relay:
    """One client, one robotd connection, bytes both ways and a deadman."""

    def __init__(self, client: socket.socket, robotd: socket.socket,
                 deadman_ms: int, log=print) -> None:
        self.client = client
        self.robotd = robotd
        self.deadman = deadman_ms / 1000 if deadman_ms > 0 else 0
        self.log = log
        self.last_from_client = time.monotonic()
        self.stopped_for_silence = False
        self.running = True

    def run(self) -> None:
        watchdog = None
        if self.deadman > 0:
            watchdog = threading.Thread(target=self._watch, daemon=True)
            watchdog.start()
        selector = selectors.DefaultSelector()
        selector.register(self.client, selectors.EVENT_READ, "client")
        selector.register(self.robotd, selectors.EVENT_READ, "robotd")
        try:
            while self.running:
                for key, _ in selector.select(timeout=0.2):
                    who = key.data
                    source = self.client if who == "client" else self.robotd
                    target = self.robotd if who == "client" else self.client
                    chunk = source.recv(65536)
                    if not chunk:
                        self.running = False
                        break
                    if who == "client":
                        # ANY BYTE FROM THE CLIENT FEEDS THE DEADMAN, not only a
                        # move: a client that is asking for state is a client
                        # that is still there, and a robot that stops because
                        # nobody drove it for a moment is a robot nobody trusts.
                        self.last_from_client = time.monotonic()
                        self.stopped_for_silence = False
                    target.sendall(chunk)
        except OSError:
            pass
        finally:
            self.running = False
            selector.close()
            if watchdog:
                watchdog.join(timeout=1)

    def _watch(self) -> None:
        while self.running:
            time.sleep(0.05)
            if self.deadman <= 0 or self.stopped_for_silence:
                continue
            quiet = time.monotonic() - self.last_from_client
            if quiet < self.deadman:
                continue
            try:
                self.robotd.sendall(STOP_LINE)
                self.stopped_for_silence = True
                self.log(f"deadman: {quiet * 1000:.0f} ms of silence, sent robot.stop")
            except OSError:
                self.running = False


def serve(host: str, port: int, socket_path: str, token: str,
          deadman_ms: int, log=print, ready=None) -> None:
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind((host, port))
    listener.listen(4)
    log(f"{VERSION} on {host}:{listener.getsockname()[1]} -> {socket_path}, "
        f"deadman {deadman_ms} ms")
    if ready:
        ready(listener.getsockname()[1])
    try:
        while True:
            client, where = listener.accept()
            threading.Thread(target=_greet,
                             args=(client, where, socket_path, token, deadman_ms, log),
                             daemon=True).start()
    finally:
        listener.close()


def _greet(client: socket.socket, where, socket_path: str, token: str,
           deadman_ms: int, log) -> None:
    client.settimeout(5)
    try:
        hello = b""
        while not hello.endswith(b"\n") and len(hello) < 4096:
            chunk = client.recv(1)
            if not chunk:
                return
            hello += chunk
        if not hello_is_valid(hello, token):
            # NAMED, AND THEN CLOSED. A client with the wrong token gets one
            # line saying which door it is at; anything more would be a probe
            # answering questions for whoever is asking them.
            client.sendall(b'{"error":"microduck-bridge: wrong or missing token"}\n')
            log(f"refused {where[0]}: wrong or missing token")
            return
        client.settimeout(None)
        robotd = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        robotd.connect(socket_path)
        client.sendall(json.dumps({"microduck": "v1", "bridge": VERSION,
                                   "deadman_ms": deadman_ms}).encode() + b"\n")
        log(f"relaying {where[0]}")
        Relay(client, robotd, deadman_ms, log=log).run()
        robotd.close()
        log(f"closed {where[0]}")
    except socket.timeout:
        log(f"refused {where[0]}: no hello within 5 s")
    except FileNotFoundError:
        client.sendall(b'{"error":"microduck-bridge: no robotd socket here"}\n')
        log(f"no socket at {socket_path} — is robotd running?")
    except OSError as error:
        log(f"{where[0]}: {error}")
    finally:
        try:
            client.close()
        except OSError:
            pass


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--socket", default=DEFAULT_SOCKET)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--host", default="0.0.0.0",
                        help="the interface to bind. The default is every "
                             "interface on the robot's own LAN; do not "
                             "port-forward it.")
    parser.add_argument("--token-file", default=os.path.expanduser("~/.microduck-bridge-token"))
    parser.add_argument("--deadman", type=int, default=DEFAULT_DEADMAN_MS,
                        help="milliseconds of client silence before robot.stop. "
                             "0 disables it, which you should not do on hardware.")
    args = parser.parse_args(argv)
    try:
        token = read_token(args.token_file)
    except Refusal as refusal:
        print(f"microduck-bridge: {refusal}", file=sys.stderr)
        return 2
    try:
        serve(args.host, args.port, args.socket, token, args.deadman)
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
