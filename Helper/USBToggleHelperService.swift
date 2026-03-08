import Foundation
import os
import USBToggleShared

final class USBToggleHelperService: NSObject, USBToggleHelperXPC {
    private let manager: USBDeviceManager
    private let logger = Logger(subsystem: USBToggleConstants.logSubsystem, category: "xpc")

    init(manager: USBDeviceManager) {
        self.manager = manager
    }

    func protocolVersion(reply: @escaping (Int) -> Void) {
        reply(USBToggleConstants.protocolVersion)
    }

    func listDevices(reply: @escaping ([USBDeviceSnapshotDTO], String?) -> Void) {
        let devices = manager.listSnapshots()
        reply(devices, nil)
    }

    func setDeviceActive(deviceID: String, active: Bool, reply: @escaping (ToggleResultDTO) -> Void) {
        logger.log("Toggle request for \(deviceID, privacy: .public), active=\(active, privacy: .public)")
        reply(manager.setDeviceActive(deviceID: deviceID, active: active))
    }

    func setRiskOverride(deviceID: String, allowed: Bool, reply: @escaping (Bool, String?) -> Void) {
        manager.setRiskOverride(deviceID: deviceID, allowed: allowed)
        reply(true, nil)
    }
}
