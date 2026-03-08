import Foundation

@objc public protocol USBToggleHelperXPC {
    func protocolVersion(reply: @escaping (Int) -> Void)
    func listDevices(reply: @escaping ([USBDeviceSnapshotDTO], String?) -> Void)
    func setDeviceActive(deviceID: String, active: Bool, reply: @escaping (ToggleResultDTO) -> Void)
    func setRiskOverride(deviceID: String, allowed: Bool, reply: @escaping (Bool, String?) -> Void)
}
