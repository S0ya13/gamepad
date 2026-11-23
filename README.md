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

## Tests

```sh
cd SharedProtocol && swift test
```
