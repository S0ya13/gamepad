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

# The running copy holds the UDP port and the virtual gamepad.
pkill -x Gamepad 2>/dev/null && sleep 1 || true
rm -rf /Applications/Gamepad.app
ditto "$DERIVED/Build/Products/Release/Gamepad.app" /Applications/Gamepad.app
open /Applications/Gamepad.app
echo "installed: /Applications/Gamepad.app (look for the gamepad icon in the menu bar)"
