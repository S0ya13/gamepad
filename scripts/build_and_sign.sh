#!/usr/bin/env bash
# Builds GamepadClient without signing, packs build/GamepadClient-unsigned.ipa and,
# if a certificate is given, signs it with zsign into build/GamepadClient-signed.ipa
# and installs it on a connected iPhone (ideviceinstaller or ios-deploy, if present).
#
# Usage:
#   scripts/build_and_sign.sh                                   # unsigned only
#   scripts/build_and_sign.sh cert.p12 'password' app.mobileprovision
#   P12_PATH=cert.p12 P12_PASSWORD=... PROVISION_PATH=app.mobileprovision scripts/build_and_sign.sh
#   NO_INSTALL=1 scripts/build_and_sign.sh ...                  # sign, but don't install
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build"
DERIVED="$OUT/DerivedData"
UNSIGNED="$OUT/GamepadClient-unsigned.ipa"
SIGNED="$OUT/GamepadClient-signed.ipa"

P12_PATH="${1:-${P12_PATH:-}}"
P12_PASSWORD="${2:-${P12_PASSWORD:-}}"
PROVISION_PATH="${3:-${PROVISION_PATH:-}}"

die() { echo "error: $*" >&2; exit 1; }

command -v xcodegen >/dev/null || die "xcodegen not found (brew install xcodegen)"

# 1. Release build, no signing.
cd "$ROOT/iOSClient"
xcodegen generate --quiet
xcodebuild build \
  -project GamepadClient.xcodeproj \
  -scheme GamepadClient \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  -quiet \
  CODE_SIGNING_ALLOWED=NO

APP="$DERIVED/Build/Products/Release-iphoneos/GamepadClient.app"
[[ -d "$APP" ]] || die "build product not found: $APP"

# 2. Payload/GamepadClient.app -> unsigned .ipa
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"
rm -f "$UNSIGNED"
(cd "$STAGE" && zip -qry "$UNSIGNED" Payload)
echo "unsigned: $UNSIGNED"

# 3. Optional signing.
if [[ -z "$P12_PATH$P12_PASSWORD$PROVISION_PATH" ]]; then
  exit 0
fi
[[ -f "$P12_PATH" ]] || die "P12_PATH is not a file: '$P12_PATH'"
[[ -f "$PROVISION_PATH" ]] || die "PROVISION_PATH is not a file: '$PROVISION_PATH'"
command -v zsign >/dev/null || die "zsign not found (brew install zsign)"

# An explicit (non-wildcard) profile only installs if the bundle id matches it, so take it from the profile.
# shortcut: partial wildcards like TEAM.com.foo.* keep the project bundle id; set it in project.yml for those.
APP_ID="$(security cms -D -i "$PROVISION_PATH" 2>/dev/null | plutil -extract Entitlements.application-identifier raw -o - -)" \
  || die "cannot read application-identifier from $PROVISION_PATH"
BUNDLE_ARGS=()
if [[ "$APP_ID" != *"*"* ]]; then
  BUNDLE_ARGS=(-b "${APP_ID#*.}")
  echo "bundle id from profile: ${APP_ID#*.}"
fi

rm -f "$SIGNED"
zsign -q -k "$P12_PATH" -p "$P12_PASSWORD" -m "$PROVISION_PATH" ${BUNDLE_ARGS[@]+"${BUNDLE_ARGS[@]}"} \
  -o "$SIGNED" "$UNSIGNED"
[[ -f "$SIGNED" ]] || die "zsign did not produce $SIGNED"
echo "signed:   $SIGNED"

# 4. Optional install.
[[ -n "${NO_INSTALL:-}" ]] && exit 0
if command -v ideviceinstaller >/dev/null; then
  # ideviceinstaller >= 1.2.0 uses subcommands; older versions use -i.
  ideviceinstaller install "$SIGNED" 2>/dev/null || ideviceinstaller -i "$SIGNED"
elif command -v ios-deploy >/dev/null; then
  unzip -q "$SIGNED" -d "$STAGE/signed"
  ios-deploy --bundle "$STAGE/signed/Payload/GamepadClient.app"
else
  echo "no ideviceinstaller / ios-deploy found: install $SIGNED manually"
fi
