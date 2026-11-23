import AVFoundation
import SharedProtocol
import SwiftUI
import VisionKit

struct SettingsView: View {
    @ObservedObject var store: ClientStore
    let onDone: () -> Void
    @State private var scanning = false
    @State private var editingLayout = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Mac") {
                    ForEach(store.pairings, id: \.name) { mac in
                        Button { store.activeName = mac.name } label: {
                            HStack {
                                Text(mac.name)
                                Spacer()
                                if mac == store.active {
                                    Text(store.ping.map { "\(Int($0.rounded())) ms" } ?? "no response")
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .tint(.primary)
                    }
                    .onDelete(perform: store.remove)
                    Button("Pair a Mac (scan QR code)", systemImage: "qrcode.viewfinder") {
                        // Ask for the camera first: the scanner reports "unavailable" until access is decided.
                        AVCaptureDevice.requestAccess(for: .video) { _ in
                            DispatchQueue.main.async { scanning = true }
                        }
                    }
                }
                Section {
                    Picker("Game", selection: $store.activeProfileID) {
                        ForEach(store.profiles) { Text($0.name).tag($0.id) }
                    }
                    LabeledContent("Name") {
                        TextField("Name", text: $store.profile.name).multilineTextAlignment(.trailing)
                    }
                    Button("Edit layout", systemImage: "square.grid.2x2") { editingLayout = true }
                    Toggle("Steer by tilting", isOn: $store.profile.tilt)
                    NavigationLink("Keyboard keys") { KeyMapView(keys: $store.profile.keys) }
                    Button("Duplicate", systemImage: "plus.square.on.square") { store.duplicateProfile() }
                    Button("Delete profile", systemImage: "trash", role: .destructive) { store.deleteProfile() }
                        .disabled(store.profiles.count < 2)
                } header: {
                    Text("Game profile")
                } footer: {
                    Text("Tilting the phone like a wheel replaces the left stick's left/right. Keyboard keys apply when the Mac is in Keyboard & mouse mode.")
                }
                Section("Sticks") {
                    slider("Size", value: $store.settings.stickRadius, in: 45...110, label: "\(Int(store.settings.stickRadius)) pt")
                    slider("Dead zone", value: $store.settings.deadZone, in: 0...0.3, label: percent(store.settings.deadZone))
                    slider("L3 at", value: $store.settings.l3Threshold, in: 0.6...0.98, label: percent(store.settings.l3Threshold))
                }
                Section {
                    Toggle("Vibration", isOn: $store.settings.haptics)
                } header: {
                    Text("Feedback")
                } footer: {
                    Text("Button taps, and the game's own rumble in the Mac's gamepad modes.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done", action: onDone) }
        }
        .fullScreenCover(isPresented: $editingLayout) {
            LayoutEditor(controls: $store.profile.controls) { editingLayout = false }
                .preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: $scanning) {
            QRScanner { pairing in
                store.add(pairing)
                scanning = false
            } onCancel: {
                scanning = false
            }
        }
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, label: String) -> some View {
        VStack(alignment: .leading) {
            LabeledContent(title, value: label).monospacedDigit()
            Slider(value: value, in: range)
        }
    }

    private func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
}

/// Keyboard & mouse mode on the Mac: what each control and stick presses for this game.
private struct KeyMapView: View {
    @Binding var keys: KeyMap

    var body: some View {
        Form {
            Section {
                Picker("Left stick", selection: $keys.leftStick) {
                    ForEach(KeyMap.Stick.allCases, id: \.self) { Text($0.title) }
                }
                Picker("Right stick", selection: $keys.rightStick) {
                    ForEach(KeyMap.Stick.allCases, id: \.self) { Text($0.title) }
                }
            } footer: {
                Text("Used when the Mac is in Keyboard & mouse mode. Gamepad modes send the real controls.")
            }
            Section("Buttons") {
                ForEach(Control.allCases, id: \.self) { control in
                    Picker(control.title, selection: key(for: control)) {
                        Text("Nothing").tag("")
                        ForEach(KeyMap.keyNames, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.navigationLink)
                }
            }
            Button("Reset to defaults") { keys = .standard }
        }
        .navigationTitle("Keyboard keys")
    }

    private func key(for control: Control) -> Binding<String> {
        Binding(get: { keys.keys[control] ?? "" }, set: { keys.keys[control] = $0.isEmpty ? nil : $0 })
    }
}

/// Live camera scanner for the Mac's pairing QR code; falls back to a hint where VisionKit can't scan.
private struct QRScanner: View {
    let onPairing: (Pairing) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    Scanner(onPairing: onPairing).ignoresSafeArea()
                } else {
                    ContentUnavailableView("Can't scan here",
                                           systemImage: "camera.slash",
                                           description: Text("Allow camera access in Settings, or open the Camera app and point it at the QR code in the Gamepad menu on the Mac."))
                }
            }
            .navigationTitle("Scan the Mac's QR code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Cancel", action: onCancel) }
        }
        .preferredColorScheme(.dark)  // a new presentation doesn't inherit the sheet's dark override
    }
}

private struct Scanner: UIViewControllerRepresentable {
    let onPairing: (Pairing) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                qualityLevel: .fast, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPairing: onPairing) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onPairing: (Pairing) -> Void
        private var done = false

        init(onPairing: @escaping (Pairing) -> Void) { self.onPairing = onPairing }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            // Other QR codes in view are ignored; only a valid pairing link closes the scanner.
            for case .barcode(let code) in items {
                guard !done, let text = code.payloadStringValue, let url = URL(string: text),
                      let pairing = Pairing(url: url) else { continue }
                done = true
                scanner.stopScanning()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onPairing(pairing)
            }
        }
    }
}
