import Foundation

public enum XPCInterfaceFactory {
    public static func helperInterface() -> NSXPCInterface {
        let interface = NSXPCInterface(with: USBToggleHelperXPC.self)

        let deviceReplyClasses = Set<AnyHashable>(
            _immutableCocoaSet: NSSet(array: [NSArray.self, USBDeviceSnapshotDTO.self])
        )
        interface.setClasses(
            deviceReplyClasses,
            for: #selector(USBToggleHelperXPC.listDevices(reply:)),
            argumentIndex: 0,
            ofReply: true
        )

        let toggleReplyClasses = Set<AnyHashable>(
            _immutableCocoaSet: NSSet(array: [ToggleResultDTO.self])
        )
        interface.setClasses(
            toggleReplyClasses,
            for: #selector(USBToggleHelperXPC.setDeviceActive(deviceID:active:reply:)),
            argumentIndex: 0,
            ofReply: true
        )
        return interface
    }
}
