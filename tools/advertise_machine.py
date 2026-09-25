#!/usr/bin/env python3
"""Keep this machine's `_duckstudio._tcp` record on the air, so Duck Studio finds it.

    python3 tools/advertise_machine.py                 # probes :8770 bench, :8771 router
    DUCK_MACHINE_NAME=robot python3 tools/advertise_machine.py

WHY, AND WHY LIKE THIS. OpenCastor's "I can't find the robot on the same network" was three
faults at once: a DHCP lease had moved, NOTHING had ever published the mDNS record, and the
fallback probed a port the robot did not serve. This runner is that lesson for Duck Studio:

- A STABLE IDENTITY. `id` is a random UUID written once to ~/.config/duckstudio/machine-id, so the
  app can follow this machine to a new address and knows it is the same machine. It says nothing
  about who owns it.
- ONLY WHAT ANSWERS. Every 30 s the bench (`GET :8770/health`) and the router (`GET :8771/health`)
  are asked; the record lists the ports that answered and no others, so the app never offers a
  router that is not running.
- RE-PUBLISHED WHEN ANYTHING CHANGES — a service coming up or going down, or this machine's
  addresses moving — which is what survives a DHCP move.

Verify with a python-zeroconf browse, NOT `avahi-browse`: on a host running avahi-daemon the two
split port 5353 and avahi-browse shows nothing, while the record is on the wire (measured for
OpenCastor, 2026-08-14).

Needs `zeroconf` (pip). Runs as a user unit; see tools/duckstudio-advertise.service.
"""

from __future__ import annotations

import logging
import os
import signal
import socket
import time
import urllib.request
import uuid
from pathlib import Path

from zeroconf import IPVersion, ServiceInfo, Zeroconf

SERVICE = "_duckstudio._tcp.local."
KIND = "duckstudio"
CHECK_SECONDS = 30
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("duckstudio.advertise")


def machine_id() -> str:
    path = Path.home() / ".config" / "duckstudio" / "machine-id"
    if path.exists() and path.read_text().strip():
        return path.read_text().strip()
    path.parent.mkdir(parents=True, exist_ok=True)
    value = str(uuid.uuid4())
    path.write_text(value + "\n")
    return value


def answers(port: int) -> bool:
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=3) as r:
            return r.status == 200
    except OSError:
        return False


def addresses() -> list[str]:
    """This machine's IPv4 addresses a phone could reach: not loopback, not link-local."""
    found = set()
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            found.add(info[4][0])
    except OSError:
        pass
    # The address the default route leaves by, which getaddrinfo may not list.
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("192.0.2.1", 9))
            found.add(s.getsockname()[0])
    except OSError:
        pass
    return sorted(a for a in found if not a.startswith(("127.", "169.254.")))


def main() -> int:
    bench_port = int(os.environ.get("DUCK_BENCH_PORT", "8770"))
    router_port = int(os.environ.get("DUCK_ROUTER_PORT", "8771"))
    name = os.environ.get("DUCK_MACHINE_NAME", socket.gethostname().split(".")[0])
    ident = machine_id()
    zc = Zeroconf(ip_version=IPVersion.V4Only)
    current: ServiceInfo | None = None
    stopping = False

    def stop(*_):
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    log.info("machine %s (%s), probing bench :%d and router :%d", name, ident, bench_port, router_port)

    while not stopping:
        txt = {"id": ident, "name": name, "kind": KIND, "v": "1"}
        if answers(bench_port):
            txt["bench_port"] = str(bench_port)
        if answers(router_port):
            txt["router_port"] = str(router_port)
        addrs = addresses()
        # The SRV port is the bench's when there is one, else the router's: a browse needs a port
        # to resolve the host, and the TXT record is what says which services there are.
        port = int(txt.get("bench_port") or txt.get("router_port") or 0)
        wanted = (tuple(sorted(txt.items())), tuple(addrs), port)
        have = None if current is None else (
            tuple(sorted((k.decode(), v.decode()) for k, v in current.properties.items())),
            tuple(sorted(current.parsed_addresses())), current.port)
        if port and addrs and wanted != have:
            info = ServiceInfo(SERVICE, f"{name}-{ident[:8]}.{SERVICE}",
                               addresses=[socket.inet_aton(a) for a in addrs], port=port,
                               properties=txt, server=f"{name}.local.")
            if current is not None:
                zc.unregister_service(current)
            zc.register_service(info)
            current = info
            log.info("published %s on %s: %s", info.name, ",".join(addrs),
                     {k: v for k, v in txt.items() if k.endswith("_port")})
        elif not port and current is not None:
            zc.unregister_service(current)
            current = None
            log.info("no service answering; record withdrawn")
        for _ in range(CHECK_SECONDS):
            if stopping:
                break
            time.sleep(1)

    if current is not None:
        zc.unregister_service(current)
    zc.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
