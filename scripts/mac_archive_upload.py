#!/usr/bin/env python3
"""Archive HEAD on the MacInCloud box and upload it to TestFlight, from the Pi.

If the Mac's home has moved (see `mac_compile_check.py`), set DUCK_MAC_HOME.

THE ONE UPLOAD PER SESSION. `mac_compile_check.py` is the free gate and runs as
often as you like; this script spends one of the ~20 uploads App Store Connect
allows a version train per day (see the TestFlight-budget rule in
~/.claude/CLAUDE.md). It refuses to run on a dirty tree, because what goes up
must be exactly one commit somebody can check out again.

HOW IT WORKS. The same paramiko connection and tarball as the compile check
(the password comes from 1Password through the service account, the tarball
is `git archive HEAD`, and it lands in ~/duck-studio on the Mac). Then
`scripts/archive_upload.sh` runs there with KEYCHAIN_PASSWORD set — the Mac's
login password, the same 1Password item — because a locked keychain fails the
archive at CodeSign with no useful error, and MacInCloud resets keychain
state between sessions.

Usage:
    python3 scripts/mac_archive_upload.py            # archive + upload HEAD
    python3 scripts/mac_archive_upload.py --dry-run  # ship and generate, no archive

Then, from the Pi (PyJWT is here, not on the Mac):
    python3 ~/projects/ios-certificates/skills/appstore-submit/testflight.py \
        status --bundle com.duckstudio.ios
"""

import argparse
import select
import shlex
import subprocess
import sys

sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent))
import mac_compile_check as base  # noqa: E402  (HOST, USER, password(), tarball())

KEY_ID = "68T2S87K39"
ISSUER_ID = "0803ec59-b64d-4014-9519-d5e8c7079f0c"


def remote_script(keychain_password: str, dry_run: bool) -> str:
    # The password is quoted for the remote shell and travels only over SSH.
    # It is exported for archive_upload.sh, which unlocks the login keychain,
    # never re-locks it for the session, and repairs the key partition list.
    steps = f"""set -e
export HOME={base.Q_HOME} CFFIXED_USER_HOME={base.Q_HOME}
export PATH=$HOME/.local/bin:$PATH
command -v xcodegen >/dev/null || {{ echo "xcodegen missing on the Mac"; exit 127; }}
rm -rf {base.Q_SRC} && mkdir -p {base.Q_SRC}
tar xzf {base.Q_HOME}/duck-studio-src.tgz -C {base.Q_SRC}
cd {base.Q_SRC}
grep -E 'CURRENT_PROJECT_VERSION|MARKETING_VERSION' DuckStudio/project.yml
"""
    if dry_run:
        return steps + "cd DuckStudio && xcodegen generate && echo DRY-RUN-OK\n"
    return steps + (
        f"export KEYCHAIN_PASSWORD={shlex.quote(keychain_password)}\n"
        f"bash scripts/archive_upload.sh {KEY_ID} {ISSUER_ID}\n"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true",
                        help="ship HEAD and regenerate the project, but do not archive or upload")
    args = parser.parse_args()

    dirty = subprocess.run(["git", "status", "--porcelain"], cwd=base.REPO,
                           capture_output=True, text=True, check=True).stdout.strip()
    if dirty:
        sys.exit("the tree is dirty — commit first; what goes up must be one commit:\n" + dirty)
    head = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=base.REPO,
                          capture_output=True, text=True, check=True).stdout.strip()

    import paramiko
    source = base.tarball(worktree=False)
    print(f"source: {source} ({source.stat().st_size // 1024} KB, HEAD {head})")

    secret = base.password()
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(base.HOST, username=base.USER, password=secret,
                   timeout=45, banner_timeout=45, auth_timeout=45)
    sftp = client.open_sftp()
    sftp.put(str(source), f"{base.REMOTE_HOME}/duck-studio-src.tgz")
    sftp.close()
    print("uploaded source, archiving on the Mac..." if not args.dry_run else "uploaded source, dry run...")

    transport = client.get_transport()
    transport.set_keepalive(30)
    channel = transport.open_session()
    channel.exec_command(remote_script(secret, args.dry_run))
    while True:
        if channel.recv_ready():
            sys.stdout.write(channel.recv(65536).decode(errors="replace"))
            sys.stdout.flush()
        if channel.recv_stderr_ready():
            sys.stderr.write(channel.recv_stderr(65536).decode(errors="replace"))
            sys.stderr.flush()
        if channel.exit_status_ready() and not channel.recv_ready():
            break
        select.select([channel], [], [], 0.5)
    status = channel.recv_exit_status()
    client.close()
    print(f"[remote exit {status}]")
    return status


if __name__ == "__main__":
    raise SystemExit(main())
