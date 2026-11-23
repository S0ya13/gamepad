import SharedProtocol
import XCTest
@testable import GamepadServerKit

final class KeyMapTests: XCTestCase {
    /// The phone offers `KeyMap.keyNames`; every one of them must press something on the Mac.
    func testEveryKeyNameHasAnOutput() {
        XCTAssertEqual(Set(KeyMap.keyNames), Set(CGEventBackend.outputs.keys))
        for name in KeyMap.standard.keys.values { XCTAssertNotNil(CGEventBackend.outputs[name], name) }
    }
}
