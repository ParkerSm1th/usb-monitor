import XCTest
@testable import USBToggleShared

final class SharedTests: XCTestCase {
    func testDeviceSnapshotRoundTripCoding() throws {
        let original = USBDeviceSnapshotDTO(
            deviceID: "1234:5678:abcd",
            displayName: "Test Device",
            vendorID: 0x1234,
            productID: 0x5678,
            serial: "abcd",
            locationID: 0x01020304,
            isActive: true,
            isExternal: true,
            riskClass: .normal,
            isBlocked: false,
            blockReason: ""
        )

        let data = try NSKeyedArchiver.archivedData(withRootObject: original, requiringSecureCoding: true)
        let decoded = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(ofClass: USBDeviceSnapshotDTO.self, from: data))

        XCTAssertEqual(decoded.deviceID, original.deviceID)
        XCTAssertEqual(decoded.displayName, original.displayName)
        XCTAssertEqual(decoded.vendorID, original.vendorID)
        XCTAssertEqual(decoded.productID, original.productID)
        XCTAssertEqual(decoded.serial, original.serial)
        XCTAssertEqual(decoded.locationID, original.locationID)
        XCTAssertEqual(decoded.isActive, original.isActive)
        XCTAssertEqual(decoded.isExternal, original.isExternal)
        XCTAssertEqual(decoded.riskClass, original.riskClass)
    }

    func testRiskClassificationForHIDAndNetwork() {
        let hidRisk = USBPolicy.classifyRisk(deviceClass: 3, interfaceClasses: [], productName: "Gaming Keyboard")
        let netRisk = USBPolicy.classifyRisk(deviceClass: 0, interfaceClasses: [2], productName: "USB Ethernet")
        let normalRisk = USBPolicy.classifyRisk(deviceClass: 0, interfaceClasses: [], productName: "Storage Stick")

        XCTAssertEqual(hidRisk, .hid)
        XCTAssertEqual(netRisk, .network)
        XCTAssertEqual(normalRisk, .normal)
    }

    func testBlockingRespectsOverrides() {
        XCTAssertTrue(USBPolicy.isBlocked(riskClass: .hid, overrideAllowed: false))
        XCTAssertFalse(USBPolicy.isBlocked(riskClass: .hid, overrideAllowed: true))
        XCTAssertFalse(USBPolicy.isBlocked(riskClass: .normal, overrideAllowed: false))
    }
}
