#!/bin/sh
# Put the bridge on the machine robotd runs on. Nothing to build, no pip.
#
# WHAT IT DOES, in the order it does it: mints a token if there is not one,
# copies two files, registers a systemd user service and an Avahi record so the
# app can find the machine without anybody typing an address, and prints the
# token. It never touches robotd, never edits its config and never asks for
# root beyond the service files.
set -eu

PREFIX="${PREFIX:-$HOME/.local}"
TOKEN_FILE="${TOKEN_FILE:-$HOME/.microduck-bridge-token}"
SOCKET="${SOCKET:-/run/robotd.sock}"
PORT="${PORT:-7788}"
DEADMAN="${DEADMAN:-700}"
HERE="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$PREFIX/bin"
install -m 755 "$HERE/microduck-bridge.py" "$PREFIX/bin/microduck-bridge"

if [ ! -f "$TOKEN_FILE" ]; then
  python3 -c "import secrets;print(secrets.token_hex(16))" > "$TOKEN_FILE"
  echo "minted a token at $TOKEN_FILE"
fi
chmod 600 "$TOKEN_FILE"

if command -v systemctl >/dev/null 2>&1; then
  mkdir -p "$HOME/.config/systemd/user"
  sed -e "s|@BIN@|$PREFIX/bin/microduck-bridge|" \
      -e "s|@SOCKET@|$SOCKET|" -e "s|@PORT@|$PORT|" \
      -e "s|@DEADMAN@|$DEADMAN|" -e "s|@TOKEN@|$TOKEN_FILE|" \
      "$HERE/microduck-bridge.service" > "$HOME/.config/systemd/user/microduck-bridge.service"
  systemctl --user daemon-reload
  systemctl --user enable --now microduck-bridge.service
  echo "service: systemctl --user status microduck-bridge"
else
  echo "no systemd here — run it yourself:"
  echo "  $PREFIX/bin/microduck-bridge --socket $SOCKET --port $PORT"
fi

if [ -d /etc/avahi/services ] && [ -w /etc/avahi/services ]; then
  sed "s|@PORT@|$PORT|" "$HERE/microduck-bridge.avahi.xml" > /etc/avahi/services/microduck-bridge.service
  echo "advertised as _robotd._tcp on $PORT"
else
  echo "not advertised: /etc/avahi/services is not writable. The app can still"
  echo "be pointed at this machine's address and port $PORT by hand."
fi

echo
echo "token (the app asks for this once):"
cat "$TOKEN_FILE"
echo
echo "THE TOKEN IS NOT A SECURITY BOUNDARY. It keeps a television out of your"
echo "robot; it does not stop anybody who can read your Wi-Fi. Do not"
echo "port-forward port $PORT."
