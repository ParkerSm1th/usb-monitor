import XCTest
@testable import USBToggleShared

final class HelperTests: XCTestCase {
    func testErrorCodeSerializationRoundTrip() {
        let allCodes: [USBToggleErrorCode] = [
            .none,
            .helperUnavailable,
            .noDevice,
            .notPermitted,
            .blockedDevice,
            .invalidRequest,
            .ioKitError,
            .timedOut,
            .unknown
        ]

        for code in allCodes {
            let serialized = code.serializedValue
            XCTAssertEqual(USBToggleErrorCode.fromSerialized(serialized), code)
        }
    }
}
