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
    python3 scripts/mac_compile_check.py --worktree --platform macos --launch
                                                     # and then run the built Mac
                                                     # app headless for 15 s
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
# instead of the usual 13 MB and the tarball turned out to hold duckbench:
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
xcodegen --version
xcodegen generate >/dev/null
set -o pipefail
xcodebuild -project DuckStudio.xcodeproj -scheme DuckStudio \
    -destination 'generic/platform=__PLATFORM__' -configuration Release \
    -skipPackagePluginValidation -skipMacroValidation \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build 2>&1 \
  | sed -e 's|/Volumes/Macintosh_HD||g' -e 's|{REMOTE_SRC}/||g' \
  | grep -v 'Stale file' \\
  | grep -E '__GREP__' | tail -__TAIL__
# `Stale file` FIRST. Xcode prints one "warning: Stale file …" per leftover
# DerivedData artefact — fifty-nine of them on 2026-09-02 — and every one
# matches `warning: [A-Z]`. With `tail -60` after them, the one real
# `error:` line scrolled off the end and a BUILD FAILED came back with no
# reason on it, which is the second worst thing a gate can do.
# THE EXIT STATUS HAS TO COME FROM xcodebuild, NOT FROM grep. Without
# `pipefail` the pipeline reports grep's status, so a BUILD FAILED whose
# errors grep matched successfully came back as exit 0 — a red build read as
# a green one, which is the single worst thing a gate can do.
status=${{PIPESTATUS[0]}}
__LAUNCH__
exit $status
"""

# THE ONLY RUNTIME CHECK THIS MAC ALLOWS. MacInCloud over ssh has no GUI session
# (`open` fails with launchd error 125, `screencapture` fails), so the built Mac
# app's own binary is started directly, left 15 s, and asked whether it is still
# alive. Still running = it got through launch without crashing; exited early =
# its status, the last lines it printed, and any crash report written since. It
# is not a look at a window. The app's own lines are prefixed `LAUNCH|` and any
# `error:` in them is respelled so `mac_gate.sh`, which reads compiler errors,
# does not mistake the app's logging for a failed build. The exit status stays
# xcodebuild's; read the LAUNCH: verdict line.
REMOTE_LAUNCH = f"""set +e
settings=$(xcodebuild -project DuckStudio.xcodeproj -scheme DuckStudio \
    -destination 'generic/platform=macOS' -configuration Release \
    -skipPackagePluginValidation -skipMacroValidation -showBuildSettings 2>/dev/null)
dir=$(printf '%s\\n' "$settings" | awk -F' = ' '$1 ~ / BUILT_PRODUCTS_DIR$/ {{print $2; exit}}')
exe=$(printf '%s\\n' "$settings" | awk -F' = ' '$1 ~ / EXECUTABLE_PATH$/ {{print $2; exit}}')
bin="$dir/$exe"
echo "LAUNCH: binary $bin" | sed -e 's|{REMOTE_HOME}|~|g'
if [ ! -x "$bin" ]; then
  echo "LAUNCH: NOT RUN, no built binary at that path"
else
  out={Q_HOME}/duck-launch.log
  stamp={Q_HOME}/duck-launch.stamp
  touch "$stamp"
  "$bin" > "$out" 2>&1 &
  pid=$!
  sleep 15
  if kill -0 "$pid" 2>/dev/null; then
    echo "LAUNCH: ALIVE after 15 s, no crash (pid $pid); stopping it"
    kill "$pid"; sleep 2; kill -9 "$pid" 2>/dev/null
  else
    wait "$pid"; code=$?
    echo "LAUNCH: EXITED before 15 s with status $code"
  fi
  tail -n 25 "$out" | sed -e 's/error:/error -/g' -e 's/^/LAUNCH| /'
  reports=$(find {Q_HOME}/Library/Logs/DiagnosticReports -newer "$stamp" -name '*Duck*' 2>/dev/null)
  if [ -n "$reports" ]; then
    echo "LAUNCH: crash report(s) written:"
    printf '%s\\n' "$reports" | sed 's/^/LAUNCH|   /'
    head -n 40 $(printf '%s\\n' "$reports" | head -n 1) | sed -e 's/error:/error -/g' -e 's/^/LAUNCH| /'
  else
    echo "LAUNCH: no crash report written"
  fi
fi
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--worktree", action="store_true",
                        help="build uncommitted changes too, not just HEAD")
    # THE SAME TARGET, TWO DESTINATIONS. Since 2026-09-30 the app target lists
    # macOS as a supported destination; `--platform macos` compiles that slice.
    # The default stays iOS so every existing caller keeps gating what ships.
    parser.add_argument("--platform", choices=["ios", "macos"], default="ios",
                        help="which destination to compile (default: ios)")
    # A conformance failure says only "does not conform"; the reason is in the
    # `note:` lines under it, which the default filter drops.
    parser.add_argument("--notes", action="store_true",
                        help="keep compiler note: lines (and a longer tail)")
    # Start the built Mac app headless for 15 s after a green build (macOS only).
    parser.add_argument("--launch", action="store_true",
                        help="after a green macOS build, run the app binary 15 s and report whether it crashed")
    args = parser.parse_args()
    if args.launch and args.platform != "macos":
        parser.error("--launch runs the Mac app, so it needs --platform macos")
    remote_build = (REMOTE_BUILD
        .replace("__LAUNCH__", REMOTE_LAUNCH if args.launch else "")
        .replace("__PLATFORM__", {"ios": "iOS", "macos": "macOS"}[args.platform])
        .replace("__GREP__", r"error:|note:|warning: [A-Z]|\*\* BUILD" if args.notes
                 else r"error:|warning: [A-Z]|\*\* BUILD")
        .replace("__TAIL__", "400" if args.notes else "60"))

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
    channel.exec_command(remote_build)
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
