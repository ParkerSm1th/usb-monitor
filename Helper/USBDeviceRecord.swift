import Foundation
import USBToggleShared

struct USBDeviceRecord {
    let deviceID: String
    let displayName: String
    let vendorID: UInt16
    let productID: UInt16
    let serial: String
    let locationID: UInt32
    let isExternal: Bool
    let riskClass: USBRiskClass
    let isBlocked: Bool
    let blockReason: String

    func snapshot(isActive: Bool) -> USBDeviceSnapshotDTO {
        USBDeviceSnapshotDTO(
            deviceID: deviceID,
            displayName: displayName,
            vendorID: vendorID,
            productID: productID,
            serial: serial,
            locationID: locationID,
            isActive: isActive,
            isExternal: isExternal,
            riskClass: riskClass,
            isBlocked: isBlocked,
            blockReason: blockReason
        )
    }
}
