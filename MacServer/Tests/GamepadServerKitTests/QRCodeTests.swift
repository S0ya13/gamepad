import CoreImage
import XCTest
@testable import GamepadServerKit

final class QRCodeTests: XCTestCase {
    /// The module grid must decode back to the text (catches a flipped or mirrored image).
    func testModulesDecodeBack() throws {
        let text = "gamepad-pair://pair?k=AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8&n=Soya%27s%20Mac&h=192.168.1.5&p=47900"
        let m = QRCode.modules(for: text)
        let scale = 8, quiet = 4, side = (m.count + 2 * quiet) * scale
        var pixels = [UInt8](repeating: 255, count: side * side)
        for (y, row) in m.enumerated() { for (x, dark) in row.enumerated() where dark {
            for dy in 0 ..< scale { for dx in 0 ..< scale {
                pixels[((y + quiet) * scale + dy) * side + (x + quiet) * scale + dx] = 0
            } }
        } }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let cg = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: side,
                         space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [], provider: provider,
                         decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: nil)!
        let found = detector.features(in: CIImage(cgImage: cg)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        XCTAssertEqual(found, [text])
    }
}
