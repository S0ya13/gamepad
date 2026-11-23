import CoreImage
import CryptoKit
import Foundation

/// The Mac's pairing key: one per Mac, shared by every phone that scanned its QR code.
public enum PairingKeyStore {
    public static let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("GamepadServer/pairing.key")

    /// The stored key, or a new one when there is none or `rotate` is set (unpairs every phone).
    public static func load(rotate: Bool) throws -> (key: Data, created: Bool) {
        if !rotate, let data = try? Data(contentsOf: file), data.count == 32 { return (data, false) }
        let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: file)
        guard FileManager.default.createFile(atPath: file.path, contents: key, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: file.path])
        }
        return (key, true)
    }
}

public enum QRCode {
    /// Dark/light modules, rows top to bottom.
    public static func modules(for text: String) -> [[Bool]] {
        let filter = CIFilter(name: "CIQRCodeGenerator")!
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        let image = filter.outputImage!
        let w = Int(image.extent.width), h = Int(image.extent.height)
        var pixels = [UInt8](repeating: 0, count: w * h)
        CIContext().render(image, toBitmap: &pixels, rowBytes: w, bounds: image.extent, format: .L8, colorSpace: nil)
        return (0 ..< h).map { y in (0 ..< w).map { x in pixels[y * w + x] < 128 } }
    }

    /// Half-block rendering with explicit black/white colors, so it scans on dark and light terminal themes.
    public static func terminalString(_ m: [[Bool]], quiet: Int = 4) -> String {
        let size = m.count
        func dark(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < size && y < size && m[y][x] }
        var out = ""
        for y in stride(from: -quiet, to: size + quiet, by: 2) {
            for x in -quiet ..< size + quiet {
                out += "\u{1B}[\(dark(x, y) ? 30 : 97);\(dark(x, y + 1) ? 40 : 107)m▀"
            }
            out += "\u{1B}[0m\n"
        }
        return out
    }
}
