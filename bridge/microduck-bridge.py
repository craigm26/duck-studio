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

import base64
import hashlib
import re
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


INSTALL_METHOD = "policy.install"
INSTALL_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
INSTALL_CAP = 8 * 1024 * 1024


class Installer:
    """THE ONE VERB THIS BRIDGE ANSWERS ITSELF, and why that is not a contradiction.

    Everything else passes through to robotd unchanged. `policy.install` cannot:
    robotd has no method that takes a file, and a network somebody searched on a
    phone reaches the robot's disk or it reaches nothing. So the bridge, which is
    the one process here that HAS a disk, takes exactly this request, writes the
    bytes where robotd loads policies from, and answers in JSON-RPC's own shape.
    It never restarts robotd and never edits a config it was not pointed at.

    WHAT IT REFUSES, BY NAME. No `--policy-dir` means the verb is off, not
    silently pointed somewhere. A name that could be a path is refused before
    anything is decoded. A sha256 is REQUIRED and checked against the bytes
    that arrived: a policy that landed one byte short would load and drive the
    servos with whatever those bytes mean. A slot is applied only when the
    bridge was given `--robotd-toml`, only to a key that table already has, and
    with a backup written first — and the answer says the change takes effect
    when robotd restarts, because it does.
    """

    def __init__(self, policy_dir: str | None, robotd_toml: str | None = None,
                 log=print) -> None:
        self.policy_dir = os.path.abspath(policy_dir) if policy_dir else None
        self.robotd_toml = os.path.abspath(robotd_toml) if robotd_toml else None
        self.log = log

    @staticmethod
    def wants(line: bytes) -> bool:
        return b'"' + INSTALL_METHOD.encode() + b'"' in line

    def handle(self, line: bytes) -> bytes:
        rpc_id = None
        try:
            message = json.loads(line.decode("utf-8"))
            rpc_id = message.get("id") if isinstance(message, dict) else None
            if not isinstance(message, dict) or message.get("method") != INSTALL_METHOD:
                raise Refusal("that line is not a policy.install request")
            result = self.install(message.get("params") or {})
            reply = {"jsonrpc": "2.0", "id": rpc_id, "result": result}
        except Refusal as why:
            reply = {"jsonrpc": "2.0", "id": rpc_id,
                     "error": {"code": -32602, "message": str(why)}}
        except (ValueError, UnicodeDecodeError) as why:
            reply = {"jsonrpc": "2.0", "id": rpc_id,
                     "error": {"code": -32700, "message": f"that line is not JSON: {why}"}}
        return json.dumps(reply, separators=(",", ":")).encode() + b"\n"

    def install(self, params: dict) -> dict:
        if not self.policy_dir:
            raise Refusal("this bridge was started without --policy-dir, so it cannot "
                          "install a policy; start it with the directory robotd loads "
                          "policies from")
        name = str(params.get("name") or "")
        if name.lower().endswith(".onnx"):
            name = name[:-5]
        if not INSTALL_NAME.match(name) or ".." in name:
            raise Refusal(f'"{name}" cannot name a policy on the robot: letters, digits, dots, '
                          "dashes and underscores, up to 64, starting with a letter or digit")
        encoded = params.get("bytes")
        if not isinstance(encoded, str) or not encoded:
            raise Refusal("policy.install needs `bytes`: the .onnx file, base64")
        try:
            data = base64.b64decode(encoded, validate=True)
        except (ValueError, TypeError):
            raise Refusal("the `bytes` field is not base64")
        if not data:
            raise Refusal("the policy is empty")
        if len(data) > INSTALL_CAP:
            raise Refusal(f"the policy is {len(data)} bytes; the shipped ones are under 1 MB "
                          f"and this bridge stops at {INSTALL_CAP}")
        claimed = str(params.get("sha256") or "").lower()
        actual = hashlib.sha256(data).hexdigest()
        if not claimed:
            raise Refusal("policy.install needs `sha256`: the digest of the bytes as sent, "
                          "so a network that arrived short is refused rather than driven")
        if claimed != actual:
            raise Refusal(f"the bytes that arrived digest to {actual[:12]}…, not the "
                          f"{claimed[:12]}… that was claimed; nothing was written")
        os.makedirs(self.policy_dir, exist_ok=True)
        path = os.path.join(self.policy_dir, f"{name}.onnx")
        tmp = f"{path}.part-{os.getpid()}"
        with open(tmp, "wb") as out:
            out.write(data)
            out.flush()
            os.fsync(out.fileno())
        os.chmod(tmp, 0o644)
        os.replace(tmp, path)
        self.log(f"policy.install: {len(data)} bytes -> {path} ({actual[:12]})")
        result = {"installed": path, "sha256": actual, "bytes": len(data),
                  "takes_effect": "when robotd next starts; this bridge does not restart it"}
        slot = params.get("slot")
        if slot is not None:
            result["slot"] = self.assign(str(slot), path)
        return result

    def assign(self, slot: str, path: str) -> dict:
        """Point one `[policy]` key at the installed file, or say why not."""
        if not INSTALL_NAME.match(slot):
            raise Refusal(f'"{slot}" is not the shape of a robotd.toml policy key')
        if not self.robotd_toml:
            return {"asked": slot, "applied": False,
                    "why": "this bridge was started without --robotd-toml; edit the "
                           f"[policy] table yourself: {slot} = \"{path}\""}
        try:
            with open(self.robotd_toml, "r", encoding="utf-8") as f:
                lines = f.read().split("\n")
        except OSError as why:
            return {"asked": slot, "applied": False, "why": f"robotd.toml could not be read: {why}"}
        in_policy = False
        found = None
        keys = []
        for index, raw in enumerate(lines):
            stripped = raw.strip()
            if stripped.startswith("["):
                in_policy = stripped == "[policy]"
                continue
            if not in_policy or not stripped or stripped.startswith("#"):
                continue
            match = re.match(r"^([A-Za-z0-9_.-]+)\s*=", stripped)
            if not match:
                continue
            keys.append(match.group(1))
            if match.group(1) == slot:
                found = index
        if found is None:
            return {"asked": slot, "applied": False,
                    "why": f"robotd.toml has no `{slot}` key under [policy]; the keys it has "
                           f"are {', '.join(keys) or 'none'}. A key robotd does not expect is "
                           "not added for it."}
        indent = lines[found][: len(lines[found]) - len(lines[found].lstrip())]
        lines[found] = f'{indent}{slot} = "{path}"'
        backup = f"{self.robotd_toml}.bak-{time.strftime('%Y%m%d-%H%M%S')}"
        with open(backup, "w", encoding="utf-8") as f:
            with open(self.robotd_toml, "r", encoding="utf-8") as original:
                f.write(original.read())
        tmp = f"{self.robotd_toml}.part-{os.getpid()}"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))
        os.replace(tmp, self.robotd_toml)
        self.log(f"policy.install: [policy] {slot} -> {path} (backup {os.path.basename(backup)})")
        return {"asked": slot, "applied": True, "backup": backup}


class Relay:
    """One client, one robotd connection, bytes both ways and a deadman."""

    def __init__(self, client: socket.socket, robotd: socket.socket,
                 deadman_ms: int, log=print, installer: Installer | None = None) -> None:
        self.client = client
        self.robotd = robotd
        self.deadman = deadman_ms / 1000 if deadman_ms > 0 else 0
        self.log = log
        self.installer = installer
        self.last_from_client = time.monotonic()
        self.stopped_for_silence = False
        self.running = True
        # WHAT THE CLIENT HAS SENT SINCE ITS LAST NEWLINE. The one verb this
        # relay answers itself has to be seen whole to be recognised, so the
        # client's bytes are forwarded a line at a time rather than a chunk at
        # a time. Every byte still reaches robotd unchanged and in order; what
        # changed is that a line waits for its own newline, which a JSON-RPC
        # message needs anyway before robotd would act on it.
        self.pending = b""

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
                        self._from_client(chunk)
                        continue
                    target.sendall(chunk)
        except OSError:
            pass
        finally:
            self.running = False
            selector.close()
            if watchdog:
                watchdog.join(timeout=1)

    def _from_client(self, chunk: bytes) -> None:
        self.pending += chunk
        while b"\n" in self.pending:
            line, self.pending = self.pending.split(b"\n", 1)
            if self.installer is not None and Installer.wants(line):
                self.client.sendall(self.installer.handle(line))
                continue
            self.robotd.sendall(line + b"\n")

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
          deadman_ms: int, log=print, ready=None,
          policy_dir: str | None = None, robotd_toml: str | None = None) -> None:
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind((host, port))
    listener.listen(4)
    # ALWAYS BUILT, so the verb is answered by the bridge whether or not it is
    # on: without a --policy-dir the answer is the refusal that names the flag,
    # not a line forwarded to a robotd that has no such method and a phone
    # waiting on a reply that never comes.
    installer = Installer(policy_dir, robotd_toml, log=log)
    log(f"{VERSION} on {host}:{listener.getsockname()[1]} -> {socket_path}, "
        f"deadman {deadman_ms} ms, policy.install "
        + (f"-> {installer.policy_dir}" if installer.policy_dir else "off (no --policy-dir)"))
    if ready:
        ready(listener.getsockname()[1])
    try:
        while True:
            client, where = listener.accept()
            threading.Thread(target=_greet,
                             args=(client, where, socket_path, token, deadman_ms, log,
                                   installer),
                             daemon=True).start()
    finally:
        listener.close()


def _greet(client: socket.socket, where, socket_path: str, token: str,
           deadman_ms: int, log, installer: Installer | None = None) -> None:
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
        # THE GREETING SAYS WHETHER INSTALL IS ON, so a phone can offer the
        # button or the sentence without asking and being refused.
        client.sendall(json.dumps({"microduck": "v1", "bridge": VERSION,
                                   "deadman_ms": deadman_ms,
                                   "policy_install": bool(installer and installer.policy_dir)})
                       .encode() + b"\n")
        log(f"relaying {where[0]}")
        Relay(client, robotd, deadman_ms, log=log, installer=installer).run()
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
    parser.add_argument("--policy-dir", default=None,
                        help="the directory robotd loads policies from; enables policy.install")
    parser.add_argument("--robotd-toml", default=None,
                        help="robotd's config, so an install can point a [policy] key at the file")
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
        serve(args.host, args.port, args.socket, token, args.deadman,
              policy_dir=args.policy_dir, robotd_toml=args.robotd_toml)
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
