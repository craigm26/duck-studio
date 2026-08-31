#!/usr/bin/env python3
"""Compile-check Duck Studio on the build Mac, from the Pi, for free.

WHY THIS EXISTS. TestFlight uploads are capped per version train — roughly
twenty per app per day — so an upload is never the way to find out whether
something builds. `xcodebuild ... CODE_SIGNING_ALLOWED=NO` is unlimited and
catches everything an upload would catch except signing. This script is the
whole loop: tar the committed tree here, put it on the Mac over SFTP, generate
the project, build, and print the errors.

WHY SFTP AND NOT `git clone`. duck-studio is private, so a clone on the Mac
needs a GitHub token — and the Mac is a rented, shared machine. A token left in
~/.git-credentials there outlives the session and the tenancy. The source goes
over the connection we already have instead, and nothing persists.

WHY PARAMIKO AND NOT ssh. MacInCloud is password auth, there is no sshpass on
the Pi, and `ssh` will not read a password from a pipe by design.

Credentials come from 1Password (Civqo, item `LA688.macincloud.com`). That item
is NOT reachable from the unattended service account, which sees Civqo but not
this entry's category — so `op` here uses the desktop integration and the
1Password app must be UNLOCKED. A locked app makes `op` hang rather than fail,
which is the trap documented in the onepassword-cli-pi-fix note.

Usage:
    python3 scripts/mac_compile_check.py             # build HEAD
    python3 scripts/mac_compile_check.py --worktree  # build the working tree,
                                                     # uncommitted changes and all
"""

import argparse
import os
import pathlib
import subprocess
import sys
import tarfile
import tempfile

HOST = "LA688.macincloud.com"
USER = "user273508"
OP_REF = "op://Civqo/LA688.macincloud.com/password"
REMOTE_HOME = f"/Users/{USER}"
REMOTE_SRC = f"{REMOTE_HOME}/duck-studio"

# Everything that must not travel: build products, the git database, and the
# agent scratch. A 13 MB tarball goes up in seconds; a .build directory does not.
EXCLUDE = {".git", ".build", ".claude", "DerivedData", "__pycache__"}


def password() -> str:
    """Read the Mac password out of 1Password via the desktop integration.

    The service-account token is explicitly stripped: it resolves a DIFFERENT,
    read-only identity that cannot see this item, and its presence silently
    wins over the desktop integration.

    `MAC_PASSWORD` short-circuits the lookup. That exists because the desktop
    app re-locks on its own timer, and a lock in the middle of a long session
    turns `op` into a sixty-second hang followed by a dead build — which is a
    bad way to lose a compile check you were part-way through. Set it for a run
    of builds; do not put it in a file that outlives the session.
    """
    cached = os.environ.get("MAC_PASSWORD")
    if cached:
        return cached.strip()
    env = {k: v for k, v in os.environ.items() if k != "OP_SERVICE_ACCOUNT_TOKEN"}
    try:
        out = subprocess.run(["op", "read", OP_REF], capture_output=True, text=True,
                             timeout=60, env=env, check=True)
    except subprocess.TimeoutExpired:
        sys.exit("op timed out. The 1Password desktop app is locked — unlock it and retry.")
    except subprocess.CalledProcessError as exc:
        sys.exit(f"op failed: {exc.stderr.strip()}")
    return out.stdout.strip()


# THIS REPO, NOT WHATEVER DIRECTORY THE SHELL HAPPENED TO BE IN.
#
# `git archive HEAD` reads the CWD, so running this by absolute path from
# another checkout silently tarred THAT repo and shipped it to the Mac to be
# built as if it were Duck Studio. Caught when the source line read 87384 KB
# instead of the usual 13 MB and the tarball turned out to hold duck-sounds:
# scene_full.mjb, mujoco.wasm and no app at all. A gate that builds the wrong
# repository is worse than one that does not run, because it answers.
REPO = pathlib.Path(__file__).resolve().parent.parent


def tarball(worktree: bool) -> pathlib.Path:
    path = pathlib.Path(tempfile.gettempdir()) / "duck-studio-src.tgz"
    if not worktree:
        with open(path, "wb") as handle:
            git = subprocess.Popen(["git", "archive", "--format=tar", "HEAD"],
                                   cwd=REPO, stdout=subprocess.PIPE)
            gzip = subprocess.Popen(["gzip", "-9"], stdin=git.stdout, stdout=handle)
            git.stdout.close()
            gzip.communicate()
        return path
    root = pathlib.Path(
        subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=REPO,
                       capture_output=True, text=True, check=True).stdout.strip())
    with tarfile.open(path, "w:gz") as archive:
        for item in sorted(root.rglob("*")):
            rel = item.relative_to(root)
            if any(part in EXCLUDE for part in rel.parts):
                continue
            if item.is_file() or item.is_symlink():
                archive.add(item, arcname=str(rel))
    return path


REMOTE_BUILD = f"""set -e
export PATH=$HOME/.local/bin:$PATH
command -v xcodegen >/dev/null || {{ echo "xcodegen missing on the Mac — see the note in this script"; exit 127; }}
rm -rf {REMOTE_SRC} && mkdir -p {REMOTE_SRC}
tar xzf {REMOTE_HOME}/duck-studio-src.tgz -C {REMOTE_SRC}
cd {REMOTE_SRC}/DuckStudio
xcodegen generate >/dev/null
set -o pipefail
xcodebuild -project DuckStudio.xcodeproj -scheme DuckStudio \
    -destination 'generic/platform=iOS' -configuration Release \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build 2>&1 \
  | sed -e 's|/Volumes/Macintosh_HD||g' -e 's|{REMOTE_SRC}/||g' \
  | grep -E 'error:|warning: [A-Z]|\\*\\* BUILD' | tail -60
# THE EXIT STATUS HAS TO COME FROM xcodebuild, NOT FROM grep. Without
# `pipefail` the pipeline reports grep's status, so a BUILD FAILED whose
# errors grep matched successfully came back as exit 0 — a red build read as
# a green one, which is the single worst thing a gate can do.
exit ${{PIPESTATUS[0]}}
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--worktree", action="store_true",
                        help="build uncommitted changes too, not just HEAD")
    args = parser.parse_args()

    try:
        import paramiko
    except ImportError:
        sys.exit("pip install --break-system-packages paramiko")

    source = tarball(args.worktree)
    print(f"source: {source} ({source.stat().st_size // 1024} KB, "
          f"{'working tree' if args.worktree else 'HEAD'})")

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(HOST, username=USER, password=password(),
                   timeout=45, banner_timeout=45, auth_timeout=45)
    sftp = client.open_sftp()
    sftp.put(str(source), f"{REMOTE_HOME}/duck-studio-src.tgz")
    sftp.close()
    print("uploaded, building...")

    transport = client.get_transport()
    transport.set_keepalive(30)
    channel = transport.open_session()
    channel.exec_command(REMOTE_BUILD)
    import select
    while True:
        if channel.recv_ready():
            sys.stdout.write(channel.recv(65536).decode(errors="replace"))
            sys.stdout.flush()
        if channel.recv_stderr_ready():
            sys.stderr.write(channel.recv_stderr(65536).decode(errors="replace"))
        if channel.exit_status_ready() and not channel.recv_ready():
            break
        select.select([channel], [], [], 0.5)
    status = channel.recv_exit_status()
    client.close()
    print(f"[xcodebuild exit {status}]")
    return status


if __name__ == "__main__":
    raise SystemExit(main())
