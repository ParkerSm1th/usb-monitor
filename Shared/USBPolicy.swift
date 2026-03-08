import Foundation
import IOKit.usb.USB

public enum USBPolicy {
    public static func isExternalDevice(infoBits: UInt32?) -> Bool {
        guard let infoBits else {
            return true
        }

        let connectedMask = UInt32(kUSBInformationDeviceIsConnectedMask.rawValue)
        let internalMask = UInt32(kUSBInformationDeviceIsInternalMask.rawValue)
        let captiveMask = UInt32(kUSBInformationDeviceIsCaptiveMask.rawValue)
        let rootHubMask = UInt32(kUSBInformationDeviceIsRootHubMask.rawValue)

        let isConnected = (infoBits & connectedMask) != 0
        let isInternal = (infoBits & internalMask) != 0
        let isCaptive = (infoBits & captiveMask) != 0
        let isRootHub = (infoBits & rootHubMask) != 0

        return isConnected && !isInternal && !isCaptive && !isRootHub
    }

    public static func classifyRisk(deviceClass: UInt8?, interfaceClasses: Set<UInt8>, productName: String) -> USBRiskClass {
        let name = productName.lowercased()
        var classes = Set<Int>(interfaceClasses.map { Int($0) })
        if let deviceClass {
            classes.insert(Int(deviceClass))
        }

        let hidClassCodes: Set<Int> = [3]
        let networkClassCodes: Set<Int> = [2, 10, 14, 224]
        let otherCriticalClassCodes: Set<Int> = [11, 13]

        if !hidClassCodes.isDisjoint(with: classes) || containsAny(name, tokens: ["keyboard", "mouse", "trackpad", "hid"]) {
            return .hid
        }

        if !networkClassCodes.isDisjoint(with: classes) || containsAny(name, tokens: ["ethernet", "network", "lan", "rndis", "cdc"]) {
            return .network
        }

        if !otherCriticalClassCodes.isDisjoint(with: classes) {
            return .otherCritical
        }

        return .normal
    }

    public static func isBlocked(riskClass: USBRiskClass, overrideAllowed: Bool) -> Bool {
        guard !overrideAllowed else {
            return false
        }
        return riskClass != .normal
    }

    public static func blockReason(for riskClass: USBRiskClass, isBlocked: Bool) -> String {
        guard isBlocked else {
            return ""
        }

        switch riskClass {
        case .hid:
            return "Blocked by default: HID-class device"
        case .network:
            return "Blocked by default: network-class device"
        case .otherCritical:
            return "Blocked by default: critical USB class"
        case .normal:
            return ""
        }
    }

    private static func containsAny(_ value: String, tokens: [String]) -> Bool {
        for token in tokens where value.contains(token) {
            return true
        }
        return false
    }
}
