#!/usr/bin/env python3
"""What the bridge does, proved against a mock robotd.

THE MOCK IS THE POINT. Nobody here has a duck on the desk, so every claim this
bridge makes is either proved against a socket that records what it was sent or
it is not proved at all. The mock speaks nothing: it accepts a connection,
records every line, and replies with whatever it was told to reply with. That
is enough, because the bridge's whole contract is that it does not interpret
the protocol.
"""

import json
import os
import socket
import tempfile
import threading
import time
import unittest

import importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("bridge", os.path.join(HERE, "microduck-bridge.py"))
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class MockRobotd:
    """A Unix socket that records lines and can push its own."""

    def __init__(self, path):
        self.path = path
        self.lines = []
        self.conns = []
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(path)
        self.server.listen(2)
        self.running = True
        threading.Thread(target=self._accept, daemon=True).start()

    def _accept(self):
        while self.running:
            try:
                conn, _ = self.server.accept()
            except OSError:
                return
            self.conns.append(conn)
            threading.Thread(target=self._read, args=(conn,), daemon=True).start()

    def _read(self, conn):
        buf = b""
        while self.running:
            try:
                chunk = conn.recv(4096)
            except OSError:
                return
            if not chunk:
                return
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                self.lines.append(line.decode())

    def push(self, text):
        for conn in self.conns:
            conn.sendall(text.encode() + b"\n")

    def close(self):
        self.running = False
        self.server.close()
        os.unlink(self.path)


class BridgeTests(unittest.TestCase):

    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.socket_path = os.path.join(self.dir, "robotd.sock")
        self.robotd = MockRobotd(self.socket_path)
        self.token = "0123456789abcdef0123456789abcdef"
        self.port = None
        ready = threading.Event()

        def note(port):
            self.port = port
            ready.set()

        self.thread = threading.Thread(
            target=bridge.serve,
            args=("127.0.0.1", 0, self.socket_path, self.token, 300),
            kwargs={"log": lambda *a: None, "ready": note}, daemon=True)
        self.thread.start()
        ready.wait(5)

    def tearDown(self):
        self.robotd.close()

    def connect(self, token=None):
        client = socket.create_connection(("127.0.0.1", self.port), timeout=5)
        hello = {"microduck": "v1", "token": token if token is not None else self.token}
        client.sendall(json.dumps(hello).encode() + b"\n")
        return client

    def line(self, sock):
        buf = b""
        while not buf.endswith(b"\n"):
            chunk = sock.recv(1)
            if not chunk:
                return buf.decode()
            buf += chunk
        return buf.decode().strip()

    # MARK: what it carries

    def testEveryByteReachesRobotdUnchanged(self):
        client = self.connect()
        self.line(client)                      # the bridge's own hello
        sent = '{"jsonrpc":"2.0","method":"robot.move","params":{"vx":0.3},"id":1}'
        client.sendall(sent.encode() + b"\n")
        time.sleep(0.2)
        self.assertIn(sent, self.robotd.lines,
                      "the relay must not rewrite a single byte of the protocol")
        client.close()

    def testRobotdsAnswerReachesTheClientUnchanged(self):
        client = self.connect()
        self.line(client)
        answer = '{"jsonrpc":"2.0","result":{"upright":true},"id":1}'
        time.sleep(0.1)
        self.robotd.push(answer)
        self.assertEqual(self.line(client), answer)
        client.close()

    # MARK: what it refuses

    def testAWrongTokenIsRefusedByName(self):
        client = self.connect(token="not-the-token-not-the-token")
        said = self.line(client)
        self.assertIn("wrong or missing token", said)
        time.sleep(0.2)
        self.assertEqual(self.robotd.lines, [],
                         "a refused client must not reach robotd at all")
        client.close()

    def testAHelloThatIsNotJsonIsRefused(self):
        client = socket.create_connection(("127.0.0.1", self.port), timeout=5)
        client.sendall(b"hello there\n")
        self.assertIn("wrong or missing token", self.line(client))
        client.close()

    def testATokenFileOtherPeopleCanReadIsRefused(self):
        path = os.path.join(self.dir, "token")
        with open(path, "w") as handle:
            handle.write("0123456789abcdef0123456789abcdef")
        os.chmod(path, 0o644)
        with self.assertRaises(bridge.Refusal) as caught:
            bridge.read_token(path)
        self.assertIn("readable or writable by other users", str(caught.exception))
        os.chmod(path, 0o600)
        self.assertEqual(bridge.read_token(path), "0123456789abcdef0123456789abcdef")

    def testAShortTokenIsRefusedWithItsLength(self):
        path = os.path.join(self.dir, "short")
        with open(path, "w") as handle:
            handle.write("tooshort")
        os.chmod(path, 0o600)
        with self.assertRaises(bridge.Refusal) as caught:
            bridge.read_token(path)
        self.assertIn("8 characters", str(caught.exception))

    # MARK: the deadman, which is the reason to prefer this to a raw relay

    def testSilenceSendsAStopAndOnlyOne(self):
        client = self.connect()
        self.line(client)
        client.sendall(b'{"jsonrpc":"2.0","method":"robot.move","params":{"vx":0.3},"id":1}\n')
        time.sleep(0.9)
        stops = [line for line in self.robotd.lines if '"robot.stop"' in line]
        self.assertEqual(len(stops), 1,
                         f"one stop for one silence, got {len(stops)}: {self.robotd.lines}")
        self.assertIn("bridge-deadman", stops[0])
        client.close()

    def testTalkingAgainRearmsTheDeadman(self):
        client = self.connect()
        self.line(client)
        client.sendall(b'{"jsonrpc":"2.0","method":"robot.move","params":{"vx":0.3},"id":1}\n')
        time.sleep(0.5)                                  # one stop by now
        client.sendall(b'{"jsonrpc":"2.0","method":"robot.move","params":{"vx":0.3},"id":2}\n')
        time.sleep(0.5)                                  # and a second
        stops = [line for line in self.robotd.lines if '"robot.stop"' in line]
        self.assertEqual(len(stops), 2, "the deadman re-arms when the client speaks again")
        client.close()

    def testAClientThatKeepsTalkingIsNeverStopped(self):
        client = self.connect()
        self.line(client)
        for _ in range(10):
            client.sendall(b'{"jsonrpc":"2.0","method":"robot.move","params":{"vx":0.3},"id":9}\n')
            time.sleep(0.1)
        stops = [line for line in self.robotd.lines if '"robot.stop"' in line]
        self.assertEqual(stops, [], "a driven robot is not stopped by its own driver")
        client.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
