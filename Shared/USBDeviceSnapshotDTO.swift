import Foundation

@objcMembers
public final class USBDeviceSnapshotDTO: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let protocolVersion: Int
    public let deviceID: String
    public let displayName: String
    public let vendorID: UInt16
    public let productID: UInt16
    public let serial: String
    public let locationID: UInt32
    public let isActive: Bool
    public let isExternal: Bool
    public let riskClass: String
    public let isBlocked: Bool
    public let blockReason: String

    public init(
        protocolVersion: Int = USBToggleConstants.protocolVersion,
        deviceID: String,
        displayName: String,
        vendorID: UInt16,
        productID: UInt16,
        serial: String,
        locationID: UInt32,
        isActive: Bool,
        isExternal: Bool,
        riskClass: USBRiskClass,
        isBlocked: Bool,
        blockReason: String
    ) {
        self.protocolVersion = protocolVersion
        self.deviceID = deviceID
        self.displayName = displayName
        self.vendorID = vendorID
        self.productID = productID
        self.serial = serial
        self.locationID = locationID
        self.isActive = isActive
        self.isExternal = isExternal
        self.riskClass = riskClass.serializedValue
        self.isBlocked = isBlocked
        self.blockReason = blockReason
        super.init()
    }

    public required init?(coder: NSCoder) {
        guard
            let deviceID = coder.decodeObject(of: NSString.self, forKey: "deviceID") as String?,
            let displayName = coder.decodeObject(of: NSString.self, forKey: "displayName") as String?,
            let serial = coder.decodeObject(of: NSString.self, forKey: "serial") as String?,
            let riskClass = coder.decodeObject(of: NSString.self, forKey: "riskClass") as String?,
            let blockReason = coder.decodeObject(of: NSString.self, forKey: "blockReason") as String?
        else {
            return nil
        }

        self.protocolVersion = coder.decodeInteger(forKey: "protocolVersion")
        self.deviceID = deviceID
        self.displayName = displayName
        self.vendorID = UInt16(coder.decodeInt32(forKey: "vendorID"))
        self.productID = UInt16(coder.decodeInt32(forKey: "productID"))
        self.serial = serial
        self.locationID = UInt32(bitPattern: coder.decodeInt32(forKey: "locationID"))
        self.isActive = coder.decodeBool(forKey: "isActive")
        self.isExternal = coder.decodeBool(forKey: "isExternal")
        self.riskClass = riskClass
        self.isBlocked = coder.decodeBool(forKey: "isBlocked")
        self.blockReason = blockReason
        super.init()
    }

    public func encode(with coder: NSCoder) {
        coder.encode(protocolVersion, forKey: "protocolVersion")
        coder.encode(deviceID as NSString, forKey: "deviceID")
        coder.encode(displayName as NSString, forKey: "displayName")
        coder.encode(Int32(vendorID), forKey: "vendorID")
        coder.encode(Int32(productID), forKey: "productID")
        coder.encode(serial as NSString, forKey: "serial")
        coder.encode(Int32(bitPattern: locationID), forKey: "locationID")
        coder.encode(isActive, forKey: "isActive")
        coder.encode(isExternal, forKey: "isExternal")
        coder.encode(riskClass as NSString, forKey: "riskClass")
        coder.encode(isBlocked, forKey: "isBlocked")
        coder.encode(blockReason as NSString, forKey: "blockReason")
    }
}
