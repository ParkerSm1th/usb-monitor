import Foundation

@objc public enum USBRiskClass: Int {
    case normal = 0
    case hid = 1
    case network = 2
    case otherCritical = 3

    public var serializedValue: String {
        switch self {
        case .normal:
            return "normal"
        case .hid:
            return "hid"
        case .network:
            return "network"
        case .otherCritical:
            return "otherCritical"
        }
    }

    public static func fromSerialized(_ value: String) -> USBRiskClass {
        switch value {
        case "hid":
            return .hid
        case "network":
            return .network
        case "otherCritical":
            return .otherCritical
        default:
            return .normal
        }
    }
}
