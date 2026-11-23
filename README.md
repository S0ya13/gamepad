# Gamepad

iPhone → Mac gamepad over UDP (LAN). Packet format: `SharedProtocol/Sources/SharedProtocol/GamepadPacket.swift`.

## Mac server

```sh
cd MacServer
swift run -c release MacServer --debug        # print state, no input emulation
swift run -c release MacServer                # keyboard + mouse emulation
swift run -c release MacServer --port 47900 --sens 15
```

Keyboard/mouse mode needs Accessibility permission for the app you run it from
(System Settings → Privacy & Security → Accessibility). Allow incoming connections if the firewall asks.

Mapping: left stick → W/A/S/D, L3 → Shift, right stick → mouse,
A → Space, B → F, X → R, Y → E, D-pad ↑↓←→ → 1/2/3/4 (edit `CGEventBackend.buttonKeys`).

All keys are released after 250 ms without packets and on Ctrl+C.

## iOS client

```sh
brew install xcodegen zsign
cd iOSClient && xcodegen && open GamepadClient.xcodeproj
```

For `Cmd + R` on a cable-connected iPhone, put your team into `iOSClient/Local.xcconfig` (git-ignored)
once, so it survives `xcodegen` regeneration:

```
DEVELOPMENT_TEAM = ABCDE12345
```

Enter the Mac IP printed by the server in the field at the bottom center. Allow Local Network access on first launch.

Layout (landscape): top 40% are buttons (left 2×2: ◀ ▲ / ▼ ▶, right 2×2: X Y / A B),
bottom 60% are floating sticks. Pushing the left stick past 88% of its radius holds L3 (sprint).

## Build and sign an .ipa

```sh
scripts/build_and_sign.sh                                       # build/GamepadClient-unsigned.ipa
scripts/build_and_sign.sh cert.p12 'password' app.mobileprovision   # + build/GamepadClient-signed.ipa, installs if possible
```

Or pass `P12_PATH`, `P12_PASSWORD`, `PROVISION_PATH` as env vars. Install uses `ideviceinstaller` (`brew install ideviceinstaller`)
or `ios-deploy` when found; `NO_INSTALL=1` skips it.

## Feather source

Add `https://raw.githubusercontent.com/S0ya13/gamepad-releases/main/source.json` in Feather → Sources.
Feather signs the unsigned build with your certificate.

Publish a new build (commit first; build number = commit count):

```sh
scripts/release.sh "what changed"
```

## Tests

```sh
cd SharedProtocol && swift test
cd iOSClient && xcodegen && xcodebuild test -scheme GamepadClient -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```
