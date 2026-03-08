import XCTest
@testable import USBToggleShared

final class AppTests: XCTestCase {
    func testProtocolVersionConstantIsStable() {
        XCTAssertEqual(USBToggleConstants.protocolVersion, 1)
    }
}
