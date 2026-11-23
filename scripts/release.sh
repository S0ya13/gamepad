#!/bin/sh
# Publishes an unsigned build of HEAD to the public Feather source S0ya13/gamepad-releases.
#   scripts/release.sh ["what changed"]
set -eu
cd "$(dirname "$0")/.."
REPO=S0ya13/gamepad-releases

[ -z "$(git status --porcelain)" ] || { echo "Commit first: every release must match a commit." >&2; exit 1; }
git push -q
BUILD=$(git rev-list --count HEAD)
NOTES="${1:-$(git log -1 --format=%s)}"

BUILD_NUMBER="$BUILD" scripts/build_and_sign.sh
cp build/GamepadClient-unsigned.ipa build/GamepadClient.ipa
gh release create "build-$BUILD" build/GamepadClient.ipa -R "$REPO" --title "Сборка $BUILD" --notes "$NOTES"
python3 -I scripts/update_source.py "$REPO" \
  build/DerivedData/Build/Products/Release-iphoneos/GamepadClient.app/Info.plist build/GamepadClient.ipa "$NOTES"
