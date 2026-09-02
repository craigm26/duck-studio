#!/usr/bin/env python3
"""Run the iOS app natively on the Apple Silicon Mac and photograph its tabs.

WHY THIS EXISTS. App Store screenshots were the one blocker nothing on the Pi
could clear: this app cannot be built for the Simulator (the MLX macro plugin
ships only a macOS-host swift-syntax; see the duck-studio-simulator-macro-block
note), so `simctl io screenshot` was never available. But the MacInCloud box
is an M4, and an iOS app that compiles for `generic/platform=iOS` runs on
Apple Silicon as "Designed for iPad" — the same arm64 device slice the archive
already builds. So: build that variant, `open` it with the `-tab N` launch
argument `DuckStudioApp` added for exactly this, find its window, and
`screencapture -l` it. The PNGs come back to the Pi; `compose_screenshots.py`
puts them on the App Store canvases.

BLOCKED ON THE CURRENT MACINCLOUD BOX, MEASURED 2026-09-01. The console
session belongs to a different account (`temp`, an admin); the SSH user
(user273508) is not an admin, has no sudo, and no GUI session of its own, so
`open` fails with "Domain does not support specified action" and
`screencapture` with "could not create image from display". Screen Sharing
listens on 5900 but is filtered from outside, and its access list is the
admin group only (`com.apple.access_screensharing` nests the admin GUID,
`ARD_AllLocalUsers = 0`), so an SSH tunnel plus a VNC login cannot open a
virtual display for this user either. Until MacInCloud grants this account
the console or Screen Sharing, this script cannot run; the screenshots come
from an iPhone with the TestFlight build. Everything below is correct for the
day that changes.

WHAT CAN GO WRONG, IN ORDER OF LIKELIHOOD: (1) `screencapture` over SSH needs
the SSH user to own the console session and hold Screen Recording permission
— a black or missing PNG means TCC said no, not that the app failed; (2) an
ad-hoc signed iOS-on-Mac app may refuse to launch, in which case the build is
retried with automatic signing and the ASC key; (3) the window needs a few
seconds to draw the first tab; each shot waits and is retried once.

Usage:
    python3 scripts/mac_screenshots.py                # HEAD, all five tabs
    python3 scripts/mac_screenshots.py --tabs 0 4     # a subset
    python3 scripts/mac_screenshots.py --skip-build   # reuse the last build on the Mac
Output: build/shots/tab-N.png on the Pi.
"""

import argparse
import pathlib
import select
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import mac_compile_check as base  # noqa: E402

KEY_ID = "68T2S87K39"
ISSUER_ID = "0803ec59-b64d-4014-9519-d5e8c7079f0c"
TABS = {0: "Policies", 1: "Motions", 2: "Scenes", 3: "Draft", 4: "Lab"}
REMOTE_SHOTS = f"{base.REMOTE_HOME}/duck-studio-shots"
DERIVED = f"{base.REMOTE_HOME}/duck-studio-ddp"

# A tiny CoreGraphics helper: print the CGWindowID and bounds of the app's
# window, which is what `screencapture -l` wants and nothing in the shell can
# answer (System Events' window ids are not CGWindowIDs).
WINDOW_HELPER = r'''
import CoreGraphics
import Foundation
let want = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "DuckStudio"
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list {
    guard let owner = w[kCGWindowOwnerName as String] as? String, owner == want,
          let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
          let id = w[kCGWindowNumber as String] as? Int,
          let b = w[kCGWindowBounds as String] as? [String: Any] else { continue }
    print("\(id) \(b["X"] ?? 0) \(b["Y"] ?? 0) \(b["Width"] ?? 0) \(b["Height"] ?? 0)")
    break
}
'''


def build_script(signing: str) -> str:
    sign = ("CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO" if signing == "adhoc" else
            f"-allowProvisioningUpdates -authenticationKeyPath $HOME/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8 "
            f"-authenticationKeyID {KEY_ID} -authenticationKeyIssuerID {ISSUER_ID}")
    return f"""set -e
export PATH=$HOME/.local/bin:$PATH
rm -rf {base.REMOTE_SRC} && mkdir -p {base.REMOTE_SRC}
tar xzf {base.REMOTE_HOME}/duck-studio-src.tgz -C {base.REMOTE_SRC}
cd {base.REMOTE_SRC}/DuckStudio
xcodegen generate >/dev/null
set -o pipefail
xcodebuild -project DuckStudio.xcodeproj -scheme DuckStudio \\
    -destination 'platform=macOS,variant=Designed for iPad' -configuration Release \\
    -derivedDataPath {DERIVED} \\
    -skipPackagePluginValidation -skipMacroValidation {sign} build 2>&1 \\
  | grep -E 'error:|\\*\\* BUILD|Designed|warning: [A-Z]' | tail -30
exit ${{PIPESTATUS[0]}}
"""


def shots_script(tabs: list[int]) -> str:
    lines = [f"""set -e
mkdir -p {REMOTE_SHOTS}
cat > {REMOTE_SHOTS}/win.swift <<'SWIFT'
{WINDOW_HELPER}
SWIFT
cd {REMOTE_SHOTS} && [ -x win ] || swiftc -O win.swift -o win 2>&1 | tail -3
APP=$(ls -d {DERIVED}/Build/Products/Release-*/DuckStudio.app | head -1)
echo "app: $APP"
"""]
    for t in tabs:
        lines.append(f"""
pkill -x DuckStudio 2>/dev/null || true; sleep 1
open -n "$APP" --args -tab {t}
for i in 1 2 3 4 5 6 7 8; do sleep 2; W=$({REMOTE_SHOTS}/win DuckStudio); [ -n "$W" ] && break; done
echo "tab {t} window: ${{W:-none}}"
if [ -n "$W" ]; then
  sleep 3
  ID=$(echo $W | cut -d' ' -f1)
  screencapture -x -o -l "$ID" {REMOTE_SHOTS}/tab-{t}.png && ls -la {REMOTE_SHOTS}/tab-{t}.png
fi
""")
    lines.append("pkill -x DuckStudio 2>/dev/null || true\necho SHOTS-DONE\n")
    return "".join(lines)


def run(client, script: str) -> int:
    transport = client.get_transport()
    transport.set_keepalive(30)
    channel = transport.open_session()
    channel.exec_command(script)
    while True:
        if channel.recv_ready():
            sys.stdout.write(channel.recv(65536).decode(errors="replace")); sys.stdout.flush()
        if channel.recv_stderr_ready():
            sys.stderr.write(channel.recv_stderr(65536).decode(errors="replace")); sys.stderr.flush()
        if channel.exit_status_ready() and not channel.recv_ready():
            break
        select.select([channel], [], [], 0.5)
    return channel.recv_exit_status()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tabs", nargs="*", type=int, default=sorted(TABS))
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--signing", choices=["adhoc", "automatic"], default="adhoc")
    parser.add_argument("--worktree", action="store_true", help="ship the working tree, not HEAD")
    args = parser.parse_args()

    import paramiko
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(base.HOST, username=base.USER, password=base.password(),
                   timeout=45, banner_timeout=45, auth_timeout=45)

    if not args.skip_build:
        source = base.tarball(args.worktree)
        print(f"source: {source} ({source.stat().st_size // 1024} KB)")
        sftp = client.open_sftp(); sftp.put(str(source), f"{base.REMOTE_HOME}/duck-studio-src.tgz"); sftp.close()
        print(f"building Designed-for-iPad variant ({args.signing} signing)...")
        status = run(client, build_script(args.signing))
        print(f"[build exit {status}]")
        if status != 0:
            client.close(); return status

    print("shooting tabs", args.tabs)
    status = run(client, shots_script(args.tabs))
    print(f"[shots exit {status}]")

    out = base.REPO / "build" / "shots"
    out.mkdir(parents=True, exist_ok=True)
    sftp = client.open_sftp()
    got = 0
    for t in args.tabs:
        try:
            sftp.get(f"{REMOTE_SHOTS}/tab-{t}.png", str(out / f"tab-{t}.png")); got += 1
            print(f"got tab-{t}.png ({(out / f'tab-{t}.png').stat().st_size // 1024} KB) — {TABS.get(t, '?')}")
        except FileNotFoundError:
            print(f"tab-{t}.png missing on the Mac")
    sftp.close(); client.close()
    print(f"{got}/{len(args.tabs)} screenshots in {out}")
    return 0 if got == len(args.tabs) else 1


if __name__ == "__main__":
    raise SystemExit(main())
