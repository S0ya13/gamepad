#!/usr/bin/env bash
# Builds the Gamepad menu bar app (Release) and installs it to /Applications, then starts it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/build/MacDerivedData"

command -v xcodegen >/dev/null || { echo "error: xcodegen not found (brew install xcodegen)" >&2; exit 1; }
cd "$ROOT/MacApp"
xcodegen generate --quiet
xcodebuild build -project GamepadMac.xcodeproj -scheme GamepadMac -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" -quiet

# A fixed identity keeps the key-press permission across reinstalls; ad-hoc changes with every build.
APP="$DERIVED/Build/Products/Release/Gamepad.app"
if security find-certificate -c "Gamepad Local Signing" >/dev/null 2>&1; then
  codesign --force --sign "Gamepad Local Signing" "$APP"
else
  echo "note: ad-hoc signed, the permission resets on every install; run scripts/make_signing_cert.sh once" >&2
fi

# The running copy holds the UDP port and the virtual gamepad.
pkill -x Gamepad 2>/dev/null && sleep 1 || true
rm -rf /Applications/Gamepad.app
ditto "$APP" /Applications/Gamepad.app
open /Applications/Gamepad.app
echo "installed: /Applications/Gamepad.app (look for the gamepad icon in the menu bar)"
