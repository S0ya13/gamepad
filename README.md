# Gamepad

Use your iPhone as a game controller for your Mac over local Wi-Fi.

The iPhone app draws a touch controller with sticks, buttons and triggers. It sends what you press to a small
menu bar app on the Mac over UDP. The Mac app turns that into keyboard and mouse input, or into a real analog
virtual gamepad that Steam, SDL games, emulators, browsers and Apple GameController games can see.

Everything is native Swift with no third-party Swift dependencies: UIKit on the phone, SwiftUI plus a Swift
package on the Mac, and a shared protocol package.

> [!NOTE]
> This was a personal project. It works for me, but I don't plan to maintain it actively. It's MIT-licensed:
> fork it, sign it yourself, change anything. Issues and PRs are welcome, but replies are not guaranteed.

## Download

Prebuilt binaries are on the [Releases page](https://github.com/S0ya13/gamepad/releases/latest):

| File | What it is |
|---|---|
| `Gamepad-mac.zip` | The Mac menu bar app (universal, ad-hoc signed, not notarized) |
| `GamepadClient-unsigned.ipa` | The iPhone app, **unsigned**. Sign it yourself, see below |

You can also build both from source (see [Build from source](#build-from-source)).

### Mac app

1. Unzip and move `Gamepad.app` to `/Applications`.
2. The app isn't notarized, so macOS blocks the first launch. Either open it once and click
   **Open Anyway** in System Settings → Privacy & Security, or clear the quarantine flag:
   ```sh
   xattr -dr com.apple.quarantine /Applications/Gamepad.app
   ```
3. A gamepad icon appears in the menu bar. Allow incoming connections if the firewall asks.

Requires macOS 13 or later.

### iPhone app

The `.ipa` is unsigned because iOS only installs apps signed with a certificate it trusts. Use any of these:

- **Sideloading tools** (AltStore, Sideloadly and similar) can sign it with a free Apple ID. With a free
  account the app expires after 7 days and has to be re-signed.
- **Feather**, if you have your own certificate. Add this source in Feather → Sources:
  `https://raw.githubusercontent.com/S0ya13/gamepad-releases/main/source.json`
- **Your own certificate with zsign**: `scripts/build_and_sign.sh cert.p12 'password' app.mobileprovision`
  builds, signs and installs the app (see [Build and sign an .ipa](#build-and-sign-an-ipa)).
- **Xcode**: build and run from source onto your phone with your own Apple ID (see [iOS client](#ios-client)).

Requires iOS 17 or later.

## Features

### iPhone

- **Game profiles.** Each profile holds a layout, a theme, tilt steering and keyboard keys for one game.
  *Duplicate* makes a new one. Three are built in:
  - **Controller**: laid out like a real pad. LT LB / Back Start / RB RT along the top, a D-pad on the left,
    an A B X Y diamond on the right, sticks between them.
  - **Standard**: the top 40% is buttons, the rest is floating sticks.
  - **Racing**: LT (brake) and RT (gas) as tall pedals, steering by tilting the phone like a wheel (45° = full lock).
- **Layout editor.** Add any control (A B X Y, D-pad, LB RB LT RT, L3 R3, Start, Back), drag to move, drag the
  handle to resize. Positions snap to a 1/40 grid. *Style* sets a button's label, shape, colour, *Stays pressed*
  (toggle) and *Turbo* (10 presses a second while held).
- **Sticks.** Empty space is the sticks: the left half is the left stick, the right half is the right stick.
  Each stick has its own size, resting spot and mode:
  - *Follows finger* (default): the base appears under your finger and is dragged along when the finger runs past the ring.
  - *Floating*: the base appears under your finger and stays there.
  - *Fixed*: the base stays put.
  - *Camera swipe*: no stick. It reads how fast the finger slides, like a touchpad, which works well for camera control.
- **Analog triggers.** LT/RT work like a pedal: the lower your finger in the trigger, the harder the pull.
- **Optional L3 by pushing the left stick to the edge** (sprint), with an adjustable threshold.
- **Haptics.** Button taps, plus the game's own rumble sent back from the Mac and played on the Taptic Engine.
- **Themes.** Midnight, Black (OLED), Neon, Sunset, Mono. A button's own colour wins over the theme.
- **Several Macs.** Pair with more than one and switch between them. The status line shows the Mac and the
  round-trip time (`● MyMac · 4 ms`).

### Mac menu bar app

- A pairing QR code, a connection indicator, and *Test vibration on the iPhone*.
- Three output modes:

  | Mode | What the Mac sees | Good for |
  |---|---|---|
  | Keyboard & mouse | Key presses and mouse movement (left stick → WASD, right stick → mouse) | Any game, no driver needed |
  | Gamepad: Steam / SDL games | An Xbox-style analog pad (via OpenJoystickDriver) | Steam, SDL games, emulators |
  | Gamepad: Apple GameController games | An Xbox Series-style pad (via OpenJoystickDriver) | GameController games, browsers (Gamepad API), cloud gaming clients |

- Mouse speed, key-press permission status, a new pairing key (unpairs every phone), launch at login.
- If the driver drops the virtual pad, the app restarts the feed automatically.

## How it works

```
iPhone (GamepadClient)                         Mac (Gamepad.app)
  touch → TouchEngine → GamepadPacket ──UDP──▶ GamepadServer ──▶ CGEventBackend  → keyboard + mouse
                    ◀── ack (ping) + rumble ──              └──▶ OJDBackend      → `ojd virtual feed` → virtual HID pad
```

- **Protocol** (`SharedProtocol`): a 16-byte little-endian payload (14 button bits, four Int16 stick axes,
  two UInt8 triggers, a sequence number) sent about 60 times a second. On the wire it is 25 bytes:
  version + payload + the first 8 bytes of HMAC-SHA256 over them. The Mac answers with signed acks (used for
  the round-trip display) and rumble messages. Default port: UDP 47900.
- **Pairing**: the Mac's QR code carries `gamepad-pair://pair?k=<key>&n=<name>&h=<ips>&p=<port>`. The phone
  finds the Mac by name over Bonjour (`_gamepad._udp`), falls back to the IPs from the QR code, and signs every
  packet with the shared key. The Mac ignores anything unsigned. The key lives in
  `~/Library/Application Support/GamepadServer/pairing.key`.
- **Safety**: all keys are released after 250 ms without packets, so a dropped connection never leaves a key held down.
- **Analog pad**: the Mac app doesn't create the virtual HID device itself. It pipes JSON frames into the
  [OpenJoystickDriver](https://github.com/xsyetopz/OpenJoystickDriver) CLI, whose driver holds Apple's
  virtual-HID entitlement.

## Setup

### Pairing

On the Mac, click the menu bar icon to show the QR code. On the iPhone, open the app → ⚙ (bottom centre) →
*Pair a Mac*, or scan the code with the Camera app. Allow Local Network access on first launch.

### Keyboard & mouse mode

macOS asks for permission to press keys: System Settings → Privacy & Security → **Device Control and Data
Access** (on macOS 26 and earlier, **Accessibility**). Relaunch the app after granting it.

The phone sends its keys from the game profile (⚙ → Keyboard keys). Defaults: left stick → W/A/S/D,
right stick → mouse, A Space, B F, X R, Y E, D-pad 1/2/3/4, LB Q, RB G, LT right click,
RT left click (from a quarter pull), L3 Shift, R3 V, Start Escape, Back Tab.

### Analog gamepad modes

1. Install [OpenJoystickDriver](https://github.com/xsyetopz/OpenJoystickDriver) and follow its setup.
2. Link its CLI as `ojd` somewhere on your `PATH`.
3. Allow it in Input Monitoring and in Device Control and Data Access.
4. Pick a gamepad mode in the Mac menu.

Mapping: A/B/X/Y → South/East/West/North, LB/RB → shoulders, LT/RT → analog triggers, Start/Back,
L3/R3 → stick clicks. The game's rumble goes back to the phone.

## Known issues

- **macOS Game Mode starves the driver.** When a game goes fullscreen, macOS turns on Game Mode, which
  deprioritises background apps. OpenJoystickDriver's service then answers in tens of seconds instead of
  milliseconds, and the game gets no input or huge lag. Fix: turn Game Mode off for that game
  (Cmd+Esc in the game → Settings → Game Mode), or play windowed. Keyboard & mouse mode isn't affected.
- **GeForce NOW**: works in *Apple GameController* mode with Game Mode off. *Steam / SDL* mode was only tested
  with Game Mode on, where it got no input. Whether it works with Game Mode off is untested.
- **Wi-Fi quality matters.** It's UDP on your LAN. A busy 2.4 GHz network adds jitter; 5 GHz or a direct
  hotspot is better.
- The downloaded Mac app is ad-hoc signed, so macOS may ask for the key-press permission again after you
  replace it with a new build.

## Ideas: where to take it

Things I'd do next if I came back to it. Pick any.

- **Create the virtual gamepad in-process.** The biggest improvement. Apps like this can make a CoreHID
  `HIDVirtualDevice` themselves, with no separate driver service for Game Mode to throttle. This needs the
  managed `com.apple.developer.hid.virtual.device` entitlement, which requires a paid Apple Developer account
  and a request to Apple. With it, `OJDBackend` could be replaced by a backend that owns the device.
- **Per-game profiles on the Mac side**: switch the output mode automatically by the frontmost app.
- **Keep the pairing key in the Keychain** instead of a file.
- **Gyro aiming**: map phone rotation to the right stick (tilt steering already exists for the left stick).
- **More controls**: Guide/Home, Share, a touchpad area, paddles. The packet still has two free button bits;
  more needs a new protocol version.
- **Physical controller remapping**: read a real controller with GameController and remap or macro it before
  it reaches the game.
- **Other servers**: the protocol is tiny and documented above. A Windows server (ViGEm) or a Linux one
  (uinput) is a weekend project.
- **An Android client** speaking the same protocol.
- **Notarized Mac builds** and a Developer ID-signed `.ipa`, so nobody has to fight Gatekeeper or re-sign.

## Build from source

Needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The Xcode
projects are generated, not committed.

### Mac menu bar app

```sh
scripts/make_signing_cert.sh  # once: a local signing identity, so the key-press permission survives reinstalls
scripts/install_mac_app.sh    # builds, installs /Applications/Gamepad.app and starts it
scripts/package_mac_app.sh    # or: build/Gamepad-mac.zip for a release
```

### Mac server (command line)

The same server without the menu bar app, handy for debugging. It uses the same port and pairing key, so run
one at a time.

```sh
cd MacServer
swift run -c release MacServer --debug        # print state, no input emulation
swift run -c release MacServer                # keyboard + mouse
swift run -c release MacServer --port 47900 --sens 15
swift run -c release MacServer --ojd sdl      # analog pad for Steam / SDL
swift run -c release MacServer --ojd gc       # analog pad for Apple GameController
```

`--pair` shows the QR code again, `--new-key` makes a new key and unpairs every phone.

### iOS client

```sh
brew install xcodegen
cd iOSClient && xcodegen && open GamepadClient.xcodeproj
```

To run on your phone with `Cmd + R`, put your team ID into `iOSClient/Local.xcconfig` (git-ignored) once, so
it survives `xcodegen` regeneration:

```
DEVELOPMENT_TEAM = ABCDE12345
```

You may also need to change `PRODUCT_BUNDLE_IDENTIFIER` in `iOSClient/project.yml` to something unique.

### Build and sign an .ipa

```sh
brew install zsign
scripts/build_and_sign.sh                                          # build/GamepadClient-unsigned.ipa
scripts/build_and_sign.sh cert.p12 'password' app.mobileprovision  # + build/GamepadClient-signed.ipa, installs if possible
```

You can also pass `P12_PATH`, `P12_PASSWORD` and `PROVISION_PATH` as environment variables. Installing uses
`ideviceinstaller` or `ios-deploy` when found; `NO_INSTALL=1` skips it.

`scripts/release.sh "notes"` publishes an unsigned build to a Feather source repo. It points at mine
(`S0ya13/gamepad-releases`); change `REPO` in the script for your fork.

### Tests

```sh
cd SharedProtocol && swift test
cd MacServer && swift test
cd iOSClient && xcodegen && xcodebuild test -scheme GamepadClient -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```

Use any simulator you have installed as the destination.

## Project layout

| Path | What's there |
|---|---|
| `SharedProtocol/` | Packet format, signing, pairing URL (Swift package, used by both apps) |
| `iOSClient/GamepadClient/` | The iPhone app: `TouchEngine` (touch → controls), `GamepadView`, `LayoutEditor`, `Profile`, `UDPClient`, `RumblePlayer` |
| `MacServer/Sources/GamepadServerKit/` | UDP server and output backends: `CGEventBackend` (keyboard/mouse), `OJDBackend` (virtual pad) |
| `MacServer/Sources/MacServer/` | Command-line server |
| `MacApp/GamepadMac/` | SwiftUI menu bar app |
| `scripts/` | Build, sign, package and release scripts |

## License

[MIT](LICENSE)
