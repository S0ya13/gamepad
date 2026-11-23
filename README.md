# Gamepad

iPhone → Mac gamepad over UDP (LAN). Packet format: `SharedProtocol/Sources/SharedProtocol/GamepadPacket.swift`.

## Mac menu bar app

```sh
scripts/install_mac_app.sh   # builds, installs /Applications/Gamepad.app and starts it
```

The gamepad icon in the menu bar shows whether the iPhone is connected and holds everything else:
the pairing QR code, the mode (keyboard & mouse, or an analog gamepad through OpenJoystickDriver for
Steam/SDL or Apple GameController games), mouse speed, Accessibility status and launch at login.
The app and the command-line server use the same port and pairing key; run one at a time.

## Mac server (command line)

```sh
cd MacServer
swift run -c release MacServer --debug        # print state, no input emulation
swift run -c release MacServer                # keyboard + mouse emulation
swift run -c release MacServer --port 47900 --sens 15
```

On first run the server prints a QR code. Scan it with the iPhone Camera and open the link in Gamepad.
The phone then finds the Mac by name over Bonjour (falls back to the IP in the QR code) and signs every
packet with the shared key; the server ignores anything unsigned. `--pair` shows the QR code again,
`--new-key` makes a new key and unpairs every phone. The key lives in
`~/Library/Application Support/GamepadServer/pairing.key`.

Keyboard/mouse mode needs Accessibility permission for the app you run it from
(System Settings → Privacy & Security → Accessibility). Allow incoming connections if the firewall asks.

Mapping: left stick → W/A/S/D, L3 → Shift, right stick → mouse,
A → Space, B → F, X → R, Y → E, D-pad ↑↓←→ → 1/2/3/4 (edit `CGEventBackend.buttonKeys`).

All keys are released after 250 ms without packets and on Ctrl+C.

### Analog virtual gamepad (OpenJoystickDriver)

Keyboard emulation turns the left stick into on/off W/A/S/D. For real analog sticks, install
[OpenJoystickDriver](https://github.com/xsyetopz/OpenJoystickDriver) (it holds Apple's virtual-HID entitlement),
link its CLI as `ojd` on `PATH`, allow it in Input Monitoring and Accessibility, then:

```sh
swift run -c release MacServer --ojd sdl   # Steam, SDL games, emulators (Xbox-style pad)
swift run -c release MacServer --ojd gc    # games using Apple GameController
```

A/B/X/Y → South/East/West/North, L3 → left stick click.

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

Pair by scanning the Mac's QR code: ⚙ (bottom center) → *Pair a Mac*, or with the Camera app (see above).
Allow Local Network access on first launch. The line next to ⚙ shows the Mac and the round trip
(`● SoyaMac · 4 ms`), or `no response` when the Mac stops answering for a second.

⚙ also holds the list of paired Macs (tap to switch, swipe to delete), stick size, dead zone,
the L3 threshold and vibration. Settings are stored on the phone.

Layout (landscape): top 40% are buttons (left 2×2: ◀ ▲ / ▼ ▶, right 2×2: X Y / A B),
bottom 60% are floating sticks. Pushing the left stick past 88% of its radius (adjustable) holds L3 (sprint).

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
