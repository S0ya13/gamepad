#!/usr/bin/env bash
# Builds the Gamepad menu bar app (Release, universal, ad-hoc signed) into build/Gamepad-mac.zip for a GitHub release.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/build/MacDerivedData"
ZIP="$ROOT/build/Gamepad-mac.zip"

command -v xcodegen >/dev/null || { echo "error: xcodegen not found (brew install xcodegen)" >&2; exit 1; }
cd "$ROOT/MacApp"
xcodegen generate --quiet
VERSION_ARGS=()
[[ -n "${BUILD_NUMBER:-}" ]] && VERSION_ARGS=(CURRENT_PROJECT_VERSION="$BUILD_NUMBER" MARKETING_VERSION="0.1.$BUILD_NUMBER")
xcodebuild build -project GamepadMac.xcodeproj -scheme GamepadMac -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" -quiet ${VERSION_ARGS[@]+"${VERSION_ARGS[@]}"}

rm -f "$ZIP"
ditto -c -k --keepParent "$DERIVED/Build/Products/Release/Gamepad.app" "$ZIP"
echo "packaged: $ZIP"
