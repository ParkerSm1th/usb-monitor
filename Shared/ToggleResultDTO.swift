import Foundation

@objcMembers
public final class ToggleResultDTO: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let protocolVersion: Int
    public let success: Bool
    public let deviceID: String
    public let newActiveState: Bool
    public let errorCode: String
    public let errorMessage: String
    public let timestamp: Date

    public init(
        protocolVersion: Int = USBToggleConstants.protocolVersion,
        success: Bool,
        deviceID: String,
        newActiveState: Bool,
        errorCode: USBToggleErrorCode,
        errorMessage: String,
        timestamp: Date = Date()
    ) {
        self.protocolVersion = protocolVersion
        self.success = success
        self.deviceID = deviceID
        self.newActiveState = newActiveState
        self.errorCode = errorCode.serializedValue
        self.errorMessage = errorMessage
        self.timestamp = timestamp
        super.init()
    }

    public required init?(coder: NSCoder) {
        guard
            let deviceID = coder.decodeObject(of: NSString.self, forKey: "deviceID") as String?,
            let errorCode = coder.decodeObject(of: NSString.self, forKey: "errorCode") as String?,
            let errorMessage = coder.decodeObject(of: NSString.self, forKey: "errorMessage") as String?,
            let timestamp = coder.decodeObject(of: NSDate.self, forKey: "timestamp") as Date?
        else {
            return nil
        }

        self.protocolVersion = coder.decodeInteger(forKey: "protocolVersion")
        self.success = coder.decodeBool(forKey: "success")
        self.deviceID = deviceID
        self.newActiveState = coder.decodeBool(forKey: "newActiveState")
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.timestamp = timestamp
        super.init()
    }

    public func encode(with coder: NSCoder) {
        coder.encode(protocolVersion, forKey: "protocolVersion")
        coder.encode(success, forKey: "success")
        coder.encode(deviceID as NSString, forKey: "deviceID")
        coder.encode(newActiveState, forKey: "newActiveState")
        coder.encode(errorCode as NSString, forKey: "errorCode")
        coder.encode(errorMessage as NSString, forKey: "errorMessage")
        coder.encode(timestamp as NSDate, forKey: "timestamp")
    }
}
