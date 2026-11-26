#!/usr/bin/env python3
"""Unit tests for the LAN JSON-RPC <-> HTTP Monocular Ground-Mapping bridge."""

import http.server
import importlib.util
import json
import os
import socket
import tempfile
import threading
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))

spec_bridge = importlib.util.spec_from_file_location("bridge", os.path.join(HERE, "microduck-bridge.py"))
bridge = importlib.util.module_from_spec(spec_bridge)
spec_bridge.loader.exec_module(bridge)

spec_mapper = importlib.util.spec_from_file_location("mapper_bridge", os.path.join(HERE, "mapper_bridge.py"))
mapper_bridge = importlib.util.module_from_spec(spec_mapper)
spec_mapper.loader.exec_module(mapper_bridge)


class MockRobotd:
    def __init__(self, path):
        self.path = path
        self.lines = []
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

    def close(self):
        self.running = False
        self.server.close()
        if os.path.exists(self.path):
            os.unlink(self.path)


class MapperBridgeTests(unittest.TestCase):

    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.socket_path = os.path.join(self.dir, "robotd.sock")
        self.robotd = MockRobotd(self.socket_path)
        self.token = "0123456789abcdef0123456789abcdef"

    def tearDown(self):
        self.robotd.close()

    def _start_bridge(self, *, mapper_url=None, mapper_local=False):
        ready = threading.Event()
        port = {}

        def note(p):
            port["n"] = p
            ready.set()

        threading.Thread(
            target=bridge.serve,
            args=("127.0.0.1", 0, self.socket_path, self.token, 400),
            kwargs={
                "log": lambda *_: None,
                "ready": note,
                "mapper_url": mapper_url,
                "mapper_local": mapper_local,
            },
            daemon=True,
        ).start()
        ready.wait(5)
        return port["n"]

    def _connect(self, port):
        sock = socket.create_connection(("127.0.0.1", port), timeout=5)
        self.addCleanup(sock.close)
        sock.sendall(json.dumps({"microduck": "v1", "token": self.token}).encode() + b"\n")
        return sock

    def _line(self, sock):
        buf = b""
        while not buf.endswith(b"\n"):
            ch = sock.recv(1)
            if not ch:
                break
            buf += ch
        return buf.decode().strip()

    def _rpc(self, sock, method, params=None, rpc_id=1):
        sock.sendall(
            json.dumps({"jsonrpc": "2.0", "id": rpc_id, "method": method, "params": params or {}}).encode() + b"\n"
        )
        return json.loads(self._line(sock))

    def testRefusesPublicInternetMapperUrl(self):
        self.assertTrue(mapper_bridge.is_local_mapper_url("http://127.0.0.1:8788"))
        self.assertTrue(mapper_bridge.is_local_mapper_url("http://microduck.local:8788"))
        self.assertTrue(mapper_bridge.is_local_mapper_url("http://192.168.1.42:8788"))
        self.assertTrue(mapper_bridge.is_local_mapper_url("http://duck.tailnet.ts.net:8788"))
        self.assertFalse(mapper_bridge.is_local_mapper_url("https://example.com/mapper"))
        with self.assertRaises(mapper_bridge.MapperBridgeRefusal):
            mapper_bridge.MapperRelay(mapper_url="https://example.com/mapper")

    def testUnconfiguredMapperReturnsNamedRefusal(self):
        port = self._start_bridge(mapper_url=None, mapper_local=False)
        client = self._connect(port)
        greeting = json.loads(self._line(client))
        self.assertFalse(greeting["mapper_bridge"])
        reply = self._rpc(client, "studio.mapper.status")
        self.assertIn("error", reply)
        self.assertIn("--mapper-url", reply["error"]["message"])

    def testLocalMapperIngestPlanKeepoutDenyAndHoldStopForwarding(self):
        port = self._start_bridge(mapper_local=True)
        client = self._connect(port)
        greeting = json.loads(self._line(client))
        self.assertTrue(greeting["mapper_bridge"])

        # 1. Status reports L0_OBSERVE default and safety boundary
        st = self._rpc(client, "studio.mapper.status")["result"]
        self.assertEqual(st["trust_tier"], "L0_OBSERVE")
        self.assertIn("ISO 13850", st["safety_boundary_statement"])

        # 2. Low-confidence ground mask fails closed
        bad_conf = self._rpc(
            client,
            "studio.mapper.ingest",
            {"pose_xytheta": [1.0, 1.0, 0.0], "mean_confidence": 0.35},
        )["result"]
        self.assertFalse(bad_conf["accepted"])
        self.assertEqual(bad_conf["decision"], "HOLD")
        self.assertEqual(bad_conf["reason"], "LOW_SEGMENTATION_CONFIDENCE")

        # 3. Valid ingest succeeds
        good = self._rpc(
            client,
            "studio.mapper.ingest",
            {"pose_xytheta": [1.2, 1.5, 0.2], "mean_confidence": 0.91},
        )["result"]
        self.assertTrue(good["accepted"])
        self.assertEqual(good["decision"], "ALLOW")

        # 4. Stairwell keep-out path is DENIED
        nominal_health = {
            "battery_v": 7.85,
            "imu_roll_deg": 1.2,
            "imu_pitch_deg": -0.8,
            "camera_age_s": 0.1,
            "estop_ok": True,
        }
        denied = self._rpc(
            client,
            "studio.mapper.plan",
            {
                "pose_xytheta": [1.2, 4.8, 0.0],
                "target_xy": [5.5, 4.8],
                "trust_tier": "L2_SUPERVISED",
                "health": nominal_health,
            },
        )["result"]
        self.assertEqual(denied["decision"], "DENY")
        self.assertEqual(denied["gate_violator"], "stairwell_dropoff")

        # 5. Low battery (< 7.0 V) triggers bipedal HOLD
        low_batt = dict(nominal_health, battery_v=6.7)
        held = self._rpc(
            client,
            "studio.mapper.plan",
            {
                "pose_xytheta": [1.0, 1.0, 0.0],
                "target_xy": [2.0, 1.0],
                "trust_tier": "L2_SUPERVISED",
                "health": low_batt,
            },
        )["result"]
        self.assertEqual(held["decision"], "HOLD")
        self.assertIn("LOW_BATTERY_SAG", held["health_verdict"]["fault_codes"])

        # 6. Safe path at L2_SUPERVISED is ALLOWED
        allowed = self._rpc(
            client,
            "studio.mapper.plan",
            {
                "pose_xytheta": [1.0, 1.0, 0.0],
                "target_xy": [2.0, 1.5],
                "trust_tier": "L2_SUPERVISED",
                "health": nominal_health,
            },
        )["result"]
        self.assertEqual(allowed["decision"], "ALLOW")

        # 7. studio.mapper.hold emits robot.stop to robotd immediately
        hold_res = self._rpc(client, "studio.mapper.hold", {"reason": "operator_button"})["result"]
        self.assertEqual(hold_res["decision"], "HOLD")
        self.assertTrue(hold_res["robot_stop_forwarded"])
        time.sleep(0.15)
        self.assertTrue(any('"robot.stop"' in line for line in self.robotd.lines))

        # 8. Deterministic SHA-256 receipt export
        receipt = self._rpc(client, "studio.mapper.receipt")["result"]
        self.assertEqual(receipt["schema"], "graft-microduck-dual-demo-bundle/1.0")
        self.assertTrue(receipt["bundle_sha256"].startswith("sha256:"))

    def testUpstreamHttpForwardingToRobotGateMapper(self):
        seen_paths = []

        class MockRobotGateHandler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                length = int(self.headers.get("Content-Length", "0"))
                body = json.loads(self.rfile.read(length).decode("utf-8"))
                seen_paths.append((self.path, body))
                resp = json.dumps({"decision": "ALLOW", "upstream": "robot-gate-microduck-mapper"}).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(resp)))
                self.end_headers()
                self.wfile.write(resp)

            def log_message(self, format, *args):
                pass

        httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), MockRobotGateHandler)
        self.addCleanup(httpd.shutdown)
        self.addCleanup(httpd.server_close)
        threading.Thread(target=httpd.serve_forever, daemon=True).start()
        http_port = httpd.server_address[1]

        port = self._start_bridge(mapper_url=f"http://127.0.0.1:{http_port}")
        client = self._connect(port)
        self._line(client)

        res = self._rpc(client, "studio.mapper.status")["result"]
        self.assertEqual(res["upstream"], "robot-gate-microduck-mapper")
        self.assertEqual(seen_paths[0][0], "/api/microduck/mapper/status")


if __name__ == "__main__":
    unittest.main(verbosity=2)
