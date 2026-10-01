#!/bin/bash
# Archive DuckStudio, sign automatically, and upload to App Store Connect
# (TestFlight). Runs headless on the Mac using an App Store Connect API key — no
# Apple ID login on the machine required. Reuses the exact flow proven on
# Exsiccatae / HearAura (team WYGG3JXWMG).
#
# Prereqs (operator, one-time):
#   1. App Store Connect -> Users and Access -> Integrations -> App Store Connect
#      API -> Team Keys -> generate a key (role: App Manager). Download the .p8.
#      The existing team key (68T2S87K39) works — it's valid for any app in team
#      WYGG3JXWMG.
#   2. Place it at: ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
#   3. Create the app record in App Store Connect for bundle com.duckstudio.ios.
#
# Usage: ./scripts/archive_upload.sh <KEY_ID> <ISSUER_ID> [iOS|macOS]
#   e.g. ./scripts/archive_upload.sh 68T2S87K39 0803ec59-b64d-4014-9519-d5e8c7079f0c
#
# PLATFORM (third argument, default iOS). Since 2026-09-30 the target builds a
# native macOS slice under the same bundle id; `macOS` archives that one and
# the export produces a signed installer package for the Mac App Store.
#
# EXPORT_ONLY=1 signs and packages into ./build/export and does NOT upload. It
# is free — no TestFlight budget is spent — and it is the way to find out that
# signing works for a platform before spending an upload on it.

set -euo pipefail

KEY_ID="${1:?usage: archive_upload.sh <KEY_ID> <ISSUER_ID>}"
ISSUER_ID="${2:?usage: archive_upload.sh <KEY_ID> <ISSUER_ID>}"
KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8"
[ -f "$KEY_PATH" ] || { echo "Missing $KEY_PATH"; exit 1; }

cd "$(dirname "$0")/../DuckStudio"
PLATFORM="${3:-iOS}"
case "$PLATFORM" in iOS|macOS) ;; *) echo "platform must be iOS or macOS"; exit 2;; esac
ARCHIVE="$HOME/DuckStudio/build/DuckStudio-$PLATFORM.xcarchive"
OPTIONS=exportOptions.plist
if [ "${EXPORT_ONLY:-0}" = 1 ]; then
  OPTIONS="$HOME/DuckStudio/build/exportOptions-local.plist"
  mkdir -p "$(dirname "$OPTIONS")"
  cp exportOptions.plist "$OPTIONS"
  /usr/libexec/PlistBuddy -c "Set :destination export" "$OPTIONS"
fi

# A locked login keychain fails the archive at the CodeSign step with no useful
# error. Unlock up front when the password is available (headless always needs it).
if [ -n "${KEYCHAIN_PASSWORD:-}" ]; then
  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$HOME/Library/Keychains/login.keychain-db"
  # Unlocking is not enough on a long run: the keychain auto-locks on its own
  # timer and this pipeline is long, so an ARCHIVE can sign clean and the
  # EXPORT die minutes later with errSecInternalComponent — the very thing the
  # unlock exists to prevent. No -l/-u arguments means "never re-lock", for
  # this session's keychain only.
  security set-keychain-settings "$HOME/Library/Keychains/login.keychain-db"
  # Unlocked is still not usable: each private key carries its own partition
  # list saying which tools may use it without a prompt, and MacInCloud resets
  # such state between sessions. When it is missing, codesign fails with
  # errSecInternalComponent even in an unlocked keychain. This grants
  # apple-tool/codesign on every key, quietly.
  security set-key-partition-list -S "apple-tool:,apple:,codesign:" -s \
    -k "$KEYCHAIN_PASSWORD" "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1 \
    || echo "WARNING: could not set key partition list"
  # The search list must hold ONLY the login keychain. A leftover ci.keychain-db
  # from the old CI experiment sat FIRST in the list carrying its own (locked)
  # copy of the Apple Distribution identity, and codesign resolves an ambiguous
  # identity name in search-list order — so export died with
  # errSecInternalComponent while the same signing worked from the login
  # keychain. Build 42 lost an afternoon to this. Enforced here every run,
  # because MacInCloud restores machine state between sessions.
  security list-keychains -d user -s "$HOME/Library/Keychains/login.keychain-db"
else
  security show-keychain-info "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null \
    || echo "WARNING: login keychain may be locked — set KEYCHAIN_PASSWORD or run: security unlock-keychain"
fi

# xcodegen is the source of truth; the .xcodeproj is gitignored + regenerated.
xcodegen generate

# See scripts/mac_compile_check.py for why these two flags and the Metal
# toolchain are needed: mlx-swift ships a build-tool plugin and Metal shaders.
xcodebuild archive \
  -project DuckStudio.xcodeproj \
  -skipPackagePluginValidation -skipMacroValidation \
  -scheme DuckStudio \
  -destination "generic/platform=$PLATFORM" \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$KEY_ID" \
  -authenticationKeyIssuerID "$ISSUER_ID"

xcodebuild -exportArchive \
  -skipPackagePluginValidation -skipMacroValidation \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$OPTIONS" \
  -exportPath "$HOME/DuckStudio/build/export-$PLATFORM" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$KEY_ID" \
  -authenticationKeyIssuerID "$ISSUER_ID"

if [ "${EXPORT_ONLY:-0}" = 1 ]; then
  echo "EXPORTED, NOT UPLOADED ($PLATFORM):"; ls -la "$HOME/DuckStudio/build/export-$PLATFORM"
  exit 0
fi
echo "Uploaded ($PLATFORM). Watch App Store Connect -> TestFlight for processing (~5-15 min)."

# Symbols upload with the build, so local archives are pure disk ballast.
rm -rf "$ARCHIVE" ~/Library/Developer/Xcode/Archives/* 2>/dev/null || true
