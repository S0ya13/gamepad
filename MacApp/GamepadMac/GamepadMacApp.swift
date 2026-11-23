import AppKit
import GamepadServerKit
import SwiftUI

@main
struct GamepadMacApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Image(systemName: model.client == nil ? "gamecontroller" : "gamecontroller.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(model.client == nil ? Color.secondary : Color.green).frame(width: 8, height: 8)
                Text(model.client.map { "iPhone connected · \($0)" } ?? "Waiting for the iPhone")
                    .font(.headline)
            }

            if let problem = model.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.callout).fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Picker("Mode", selection: $model.mode) {
                ForEach(AppModel.Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            switch model.mode {
            case .keyboard:
                if !model.hasAccessibility {
                    HStack {
                        Label("Needs Device Control access to press keys", systemImage: "lock.fill")
                            .font(.callout).foregroundStyle(.orange)
                        Button("Allow…") { model.refreshAccessibility(prompt: true) }
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mouse speed: \(Int(model.sensitivity))").font(.callout)
                    Slider(value: $model.sensitivity, in: 3 ... 60, step: 1)
                }
                Text("Keys for each game are set on the iPhone: ⚙ → Keyboard keys.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            case .gamepadSDL, .gamepadGC:
                Text("Analog sticks through OpenJoystickDriver. It must be running with Input Monitoring allowed.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            DisclosureGroup("Pair an iPhone", isExpanded: $model.showPairing) {
                if let pairing = model.pairing {
                    VStack(spacing: 8) {
                        QRImage(text: pairing.url.absoluteString).frame(width: 220, height: 220)
                        Text("Scan with the iPhone Camera and open the link in Gamepad.")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("New key (unpairs every phone)") { model.newKey() }.font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                }
            }

            Divider()

            Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
            Button("Quit Gamepad") { model.quit() }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { model.refreshAccessibility() }
    }
}

/// Crisp QR code: one pixel per module, scaled without smoothing, white quiet zone.
struct QRImage: View {
    let text: String

    var body: some View {
        if let image = Self.render(QRCode.modules(for: text)) {
            Image(decorative: image, scale: 1).interpolation(.none).resizable()
        }
    }

    static func render(_ m: [[Bool]], quiet: Int = 4) -> CGImage? {
        let side = m.count + 2 * quiet
        var pixels = [UInt8](repeating: 255, count: side * side)
        for (y, row) in m.enumerated() { for (x, dark) in row.enumerated() where dark {
            pixels[(y + quiet) * side + x + quiet] = 0
        } }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: side,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [], provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
