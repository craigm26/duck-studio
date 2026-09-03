#!/usr/bin/env python3
"""A robotd-shaped socket for people without a duck.

IT ANSWERS THE SHAPE AND CLAIMS NOTHING ELSE. It speaks JSON-RPC lines, accepts
every method, answers with a plausible result and records what it was asked, so
the bridge and the app can be exercised end to end on a laptop. It is not a
simulator: nothing here has physics, and a state it returns is a constant. Use
the bench for a duck that moves.
"""
import argparse, json, os, socket, threading, time

def serve(path):
    if os.path.exists(path):
        os.unlink(path)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(path)
    server.listen(4)
    print(f"mock robotd on {path} — every method accepted, nothing simulated")
    while True:
        conn, _ = server.accept()
        threading.Thread(target=talk, args=(conn,), daemon=True).start()

def talk(conn):
    buf = b""
    while True:
        chunk = conn.recv(4096)
        if not chunk:
            return
        buf += chunk
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            try:
                call = json.loads(line)
            except json.JSONDecodeError:
                continue
            method = call.get("method", "?")
            print(f"  <- {method} {json.dumps(call.get('params', {}))[:80]}")
            if call.get("id") is None:
                continue
            conn.sendall(json.dumps({
                "jsonrpc": "2.0", "id": call["id"],
                "result": {"ok": True, "method": method, "t": round(time.time(), 3)},
            }).encode() + b"\n")

if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--socket", default="/tmp/mock-robotd.sock")
    serve(p.parse_args().socket)
