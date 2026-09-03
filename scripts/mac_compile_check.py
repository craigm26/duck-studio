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
import shlex
import os
import pathlib
import subprocess
import sys
import tarfile
import tempfile

HOST = "LA688.macincloud.com"
USER = "user273508"
OP_REF = "op://Civqo/LA688.macincloud.com/password"
# THE HOME CAN MOVE. On 2026-09-01 the external volume that carries every user
# home on LA688 came unmounted; `/Users/user273508` is a symlink into it and
# went dead, while the Data volume remounted at a different path with the
# keychain, the ASC key and xcodegen all intact. `DUCK_MAC_HOME` points every
# remote path — and `$HOME` for the tools that read it — at wherever the home
# actually is today, without editing this file under pressure.
#
# `$HOME` IS NOT ENOUGH, AND `CFFIXED_USER_HOME` IS THE VARIABLE THAT IS.
# xcodebuild, SwiftPM and `security` ask Foundation for the home, and Foundation
# asks directory services — which still answers the dead symlink — unless
# `CFFIXED_USER_HOME` is set, which Foundation honours over both. With only
# `$HOME` moved, package resolution died trying to create DerivedData under the
# dead path ("The file “Users” couldn’t be saved in the folder “macOS”"); with
# both moved, it resolved all fifteen packages. Measured 2026-09-01.
REMOTE_HOME = os.environ.get("DUCK_MAC_HOME", f"/Users/{USER}")
REMOTE_SRC = f"{REMOTE_HOME}/duck-studio"
Q_HOME = shlex.quote(REMOTE_HOME)
Q_SRC = shlex.quote(REMOTE_SRC)

# Everything that must not travel: build products, the git database, and the
# agent scratch. A 13 MB tarball goes up in seconds; a .build directory does not.
EXCLUDE = {".git", ".build", ".claude", "DerivedData", "__pycache__"}


def password() -> str:
    """Read the Mac password out of 1Password.

    THE SERVICE ACCOUNT FIRST, AND THE COMMENT THAT USED TO BE HERE WAS WRONG.
    It said the service-account token "resolves a DIFFERENT, read-only identity
    that cannot see this item" and stripped it on that basis — so every build
    borrowed authorisation from the desktop app and inherited its lock state.
    That cost most of a day: the app re-locks on a short timer, and a gate that
    cannot read a password is a gate that does not run.

    Checked 2026-08-31: the `pi-unattended-deploys` service account has READ on
    the Civqo vault, this item is in Civqo, and `op read` with the token returns
    it in a clean environment. A service account never locks, which is the whole
    reason it exists.

    The desktop integration stays as the fallback for a machine that has no
    token. `MAC_PASSWORD` still short-circuits both.
    """
    cached = os.environ.get("MAC_PASSWORD")
    if cached:
        return cached.strip()

    env = dict(os.environ)
    if "OP_SERVICE_ACCOUNT_TOKEN" not in env:
        # Sourced from ~/.bashrc for interactive shells; a subprocess spawned by
        # an agent does not necessarily have it.
        account = pathlib.Path.home() / ".config/op/service-account.env"
        if account.exists():
            for line in account.read_text().splitlines():
                line = line.strip().removeprefix("export ").strip()
                if line.startswith("OP_SERVICE_ACCOUNT_TOKEN="):
                    env["OP_SERVICE_ACCOUNT_TOKEN"] = line.split("=", 1)[1].strip().strip("'\"")

    attempts = []
    if env.get("OP_SERVICE_ACCOUNT_TOKEN"):
        attempts.append(("service account", env))
    # Desktop integration: same environment WITHOUT the token, because the two
    # identities cannot both be presented.
    desktop = {k: v for k, v in os.environ.items() if k != "OP_SERVICE_ACCOUNT_TOKEN"}
    attempts.append(("desktop app", desktop))

    problems = []
    for label, environment in attempts:
        try:
            out = subprocess.run(["op", "read", OP_REF], capture_output=True, text=True,
                                 timeout=60, env=environment, check=True)
            secret = out.stdout.strip()
            if secret:
                return secret
            problems.append(f"{label}: empty answer")
        except subprocess.TimeoutExpired:
            problems.append(f"{label}: timed out (the desktop app is locked)")
        except subprocess.CalledProcessError as exc:
            problems.append(f"{label}: {exc.stderr.strip().splitlines()[0] if exc.stderr.strip() else 'failed'}")

    sys.exit("could not read the Mac password from 1Password.\n  "
             + "\n  ".join(problems)
             + "\nSet MAC_PASSWORD for this run, or fix the service-account token at "
               "~/.config/op/service-account.env.")


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


# TWO FLAGS AND A TOOLCHAIN, ALL THREE FOUND THE HARD WAY.
#
# `-skipPackagePluginValidation`: mlx-swift ships a build-tool plugin called
# CudaBuild. Xcode will not run an unvalidated package plugin in a headless
# build and fails with "Validate plug-in ... in package mlx-swift" and no
# further explanation. `-skipMacroValidation` is the same rule for the
# swift-syntax macros MLX pulls in.
#
# And the build machine needs the Metal toolchain, which Xcode 26 made a
# separate 688 MB component: without it MLX's shaders stop at "cannot execute
# tool 'metal' due to missing Metal Toolchain". Install once per machine with
#     xcodebuild -downloadComponent MetalToolchain
REMOTE_BUILD = f"""set -e
export HOME={Q_HOME} CFFIXED_USER_HOME={Q_HOME}
export PATH=$HOME/.local/bin:$PATH
command -v xcodegen >/dev/null || {{ echo "xcodegen missing on the Mac — see the note in this script"; exit 127; }}
rm -rf {Q_SRC} && mkdir -p {Q_SRC}
tar xzf {Q_HOME}/duck-studio-src.tgz -C {Q_SRC}
cd {Q_SRC}/DuckStudio
xcodegen generate >/dev/null
set -o pipefail
xcodebuild -project DuckStudio.xcodeproj -scheme DuckStudio \
    -destination 'generic/platform=iOS' -configuration Release \
    -skipPackagePluginValidation -skipMacroValidation \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build 2>&1 \
  | sed -e 's|/Volumes/Macintosh_HD||g' -e 's|{REMOTE_SRC}/||g' \
  | grep -v 'Stale file' \\
  | grep -E 'error:|warning: [A-Z]|\\*\\* BUILD' | tail -60
# `Stale file` FIRST. Xcode prints one "warning: Stale file …" per leftover
# DerivedData artefact — fifty-nine of them on 2026-09-02 — and every one
# matches `warning: [A-Z]`. With `tail -60` after them, the one real
# `error:` line scrolled off the end and a BUILD FAILED came back with no
# reason on it, which is the second worst thing a gate can do.
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
