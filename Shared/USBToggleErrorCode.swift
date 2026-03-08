import Foundation

@objc public enum USBToggleErrorCode: Int {
    case none = 0
    case helperUnavailable = 1
    case noDevice = 2
    case notPermitted = 3
    case blockedDevice = 4
    case invalidRequest = 5
    case ioKitError = 6
    case timedOut = 7
    case unknown = 255

    public var serializedValue: String {
        switch self {
        case .none:
            return "none"
        case .helperUnavailable:
            return "helperUnavailable"
        case .noDevice:
            return "noDevice"
        case .notPermitted:
            return "notPermitted"
        case .blockedDevice:
            return "blockedDevice"
        case .invalidRequest:
            return "invalidRequest"
        case .ioKitError:
            return "ioKitError"
        case .timedOut:
            return "timedOut"
        case .unknown:
            return "unknown"
        }
    }

    public static func fromSerialized(_ value: String) -> USBToggleErrorCode {
        switch value {
        case "none":
            return .none
        case "helperUnavailable":
            return .helperUnavailable
        case "noDevice":
            return .noDevice
        case "notPermitted":
            return .notPermitted
        case "blockedDevice":
            return .blockedDevice
        case "invalidRequest":
            return .invalidRequest
        case "ioKitError":
            return .ioKitError
        case "timedOut":
            return .timedOut
        default:
            return .unknown
        }
    }
}
