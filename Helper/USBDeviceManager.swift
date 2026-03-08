import Foundation
import IOKit
import IOKit.usb.USB
import os
import USBToggleShared

private let helperLogger = Logger(subsystem: USBToggleConstants.logSubsystem, category: "helper")

private func usbDeviceChangeCallback(_ refcon: UnsafeMutableRawPointer?, _ iterator: io_iterator_t) {
    guard let refcon else {
        return
    }

    let manager = Unmanaged<USBDeviceManager>.fromOpaque(refcon).takeUnretainedValue()
    manager.handleNotification(iterator: iterator)
}

final class USBDeviceManager: @unchecked Sendable {
    private struct ResolvedIdentity {
        let vendorID: UInt16
        let productID: UInt16
        let serial: String
        let locationID: UInt32
        let displayName: String
    }

    private let queue = DispatchQueue(label: "com.parker.usbtoggle.helper.device-manager")
    private var inactiveDeviceIDs = Set<String>()
    private var riskOverrides: [String: Bool] = [:]

    private var notificationPort: IONotificationPortRef?
    private var firstMatchIterator: io_iterator_t = 0
    private var terminatedIterator: io_iterator_t = 0

    init() {
        setupNotifications()
    }

    deinit {
        if firstMatchIterator != 0 {
            IOObjectRelease(firstMatchIterator)
        }
        if terminatedIterator != 0 {
            IOObjectRelease(terminatedIterator)
        }
        if let notificationPort {
            IONotificationPortDestroy(notificationPort)
        }
    }

    func listSnapshots() -> [USBDeviceSnapshotDTO] {
        queue.sync {
            let records = enumerateExternalRecordsLocked()
            pruneInactiveStateLocked(validDeviceIDs: Set(records.map(\.deviceID)))

            return records
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
                .map { record in
                    let isActive = !inactiveDeviceIDs.contains(record.deviceID)
                    return record.snapshot(isActive: isActive)
                }
        }
    }

    func setRiskOverride(deviceID: String, allowed: Bool) {
        queue.sync {
            riskOverrides[deviceID] = allowed
        }
    }

    func setDeviceActive(deviceID: String, active: Bool) -> ToggleResultDTO {
        queue.sync {
            guard let (service, record) = findExternalDeviceLocked(deviceID: deviceID) else {
                return ToggleResultDTO(
                    success: false,
                    deviceID: deviceID,
                    newActiveState: active,
                    errorCode: .noDevice,
                    errorMessage: "Device is no longer connected"
                )
            }
            defer { IOObjectRelease(service) }

            if record.isBlocked {
                return ToggleResultDTO(
                    success: false,
                    deviceID: deviceID,
                    newActiveState: !active,
                    errorCode: .blockedDevice,
                    errorMessage: record.blockReason
                )
            }

            let currentlyActive = !inactiveDeviceIDs.contains(deviceID)
            if currentlyActive == active {
                return ToggleResultDTO(
                    success: true,
                    deviceID: deviceID,
                    newActiveState: active,
                    errorCode: .none,
                    errorMessage: "No change required"
                )
            }

            let options: UInt32 = active
                ? UInt32(kUSBReEnumerateReleaseDeviceMask.rawValue)
                : UInt32(kUSBReEnumerateCaptureDeviceMask.rawValue)

            let status = usb_toggle_reenumerate(service, options)
            if status == kIOReturnSuccess {
                if active {
                    inactiveDeviceIDs.remove(deviceID)
                } else {
                    inactiveDeviceIDs.insert(deviceID)
                }

                return ToggleResultDTO(
                    success: true,
                    deviceID: deviceID,
                    newActiveState: active,
                    errorCode: .none,
                    errorMessage: ""
                )
            }

            let mappedCode = mapIOKitStatus(status)
            let description = ioKitErrorDescription(status)
            helperLogger.error("Re-enumerate failed for \(deviceID, privacy: .public), status=\(status, privacy: .public), message=\(description, privacy: .public)")

            return ToggleResultDTO(
                success: false,
                deviceID: deviceID,
                newActiveState: currentlyActive,
                errorCode: mappedCode,
                errorMessage: description
            )
        }
    }

    private func setupNotifications() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            helperLogger.error("Failed to create IONotificationPort")
            return
        }
        notificationPort = port

        if let runLoopSource = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }

        registerNotifications(port: port)
    }

    private func registerNotifications(port: IONotificationPortRef) {
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let firstMatchStatus = IOServiceAddMatchingNotification(
            port,
            kIOFirstMatchNotification,
            IOServiceMatching("IOUSBHostDevice"),
            usbDeviceChangeCallback,
            context,
            &firstMatchIterator
        )

        if firstMatchStatus == kIOReturnSuccess {
            consume(iterator: firstMatchIterator)
        } else {
            helperLogger.error("Failed to register first-match notification: \(firstMatchStatus, privacy: .public)")
        }

        let terminatedStatus = IOServiceAddMatchingNotification(
            port,
            kIOTerminatedNotification,
            IOServiceMatching("IOUSBHostDevice"),
            usbDeviceChangeCallback,
            context,
            &terminatedIterator
        )

        if terminatedStatus == kIOReturnSuccess {
            consume(iterator: terminatedIterator)
        } else {
            helperLogger.error("Failed to register terminated notification: \(terminatedStatus, privacy: .public)")
        }
    }

    fileprivate func handleNotification(iterator: io_iterator_t) {
        consume(iterator: iterator)
        queue.async {
            let records = self.enumerateExternalRecordsLocked()
            self.pruneInactiveStateLocked(validDeviceIDs: Set(records.map(\.deviceID)))
        }
    }

    private func consume(iterator: io_iterator_t) {
        var service = IOIteratorNext(iterator)
        while service != 0 {
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }

    private func enumerateExternalRecordsLocked() -> [USBDeviceRecord] {
        var records: [USBDeviceRecord] = []
        var seenRegistryIDs = Set<UInt64>()
        var seenDeviceIDs = Set<String>()

        for className in ["IOUSBHostDevice", "IOUSBDevice"] {
            guard let matching = IOServiceMatching(className) else {
                continue
            }

            var iterator: io_iterator_t = 0
            let status = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
            guard status == kIOReturnSuccess else {
                helperLogger.error("Failed to query \(className, privacy: .public): \(status, privacy: .public)")
                continue
            }

            defer { IOObjectRelease(iterator) }

            var service = IOIteratorNext(iterator)
            while service != 0 {
                defer { IOObjectRelease(service) }

                var registryID: UInt64 = 0
                if IORegistryEntryGetRegistryEntryID(service, &registryID) == kIOReturnSuccess {
                    if seenRegistryIDs.contains(registryID) {
                        service = IOIteratorNext(iterator)
                        continue
                    }
                    seenRegistryIDs.insert(registryID)
                }

                if let record = buildRecord(service: service), record.isExternal {
                    if seenDeviceIDs.contains(record.deviceID) {
                        service = IOIteratorNext(iterator)
                        continue
                    }
                    seenDeviceIDs.insert(record.deviceID)
                    records.append(record)
                }

                service = IOIteratorNext(iterator)
            }
        }

        return records
    }

    private func findExternalDeviceLocked(deviceID: String) -> (io_service_t, USBDeviceRecord)? {
        for className in ["IOUSBHostDevice", "IOUSBDevice"] {
            guard let matching = IOServiceMatching(className) else {
                continue
            }

            var iterator: io_iterator_t = 0
            let status = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
            guard status == kIOReturnSuccess else {
                continue
            }
            defer { IOObjectRelease(iterator) }

            var service = IOIteratorNext(iterator)
            while service != 0 {
                if let record = buildRecord(service: service), record.isExternal, record.deviceID == deviceID {
                    return (service, record)
                }

                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
        }

        return nil
    }

    private func buildRecord(service: io_service_t) -> USBDeviceRecord? {
        let identity = resolveIdentity(for: service)
        let vendorID = identity.vendorID
        let productID = identity.productID
        let serial = identity.serial
        let locationID = identity.locationID
        let displayName = identity.displayName

        if vendorID == 0, productID == 0, locationID == 0, serial.isEmpty {
            return nil
        }

        let stableID: String
        if !serial.isEmpty {
            stableID = String(format: "%04x:%04x:%@", vendorID, productID, serial)
        } else if locationID != 0 || vendorID != 0 || productID != 0 {
            stableID = String(format: "%04x:%04x:%08x", vendorID, productID, locationID)
        } else {
            var registryID: UInt64 = 0
            _ = IORegistryEntryGetRegistryEntryID(service, &registryID)
            stableID = String(format: "registry:%016llx", registryID)
        }

        var infoBits: UInt32 = 0
        let infoStatus = usb_toggle_get_device_information(service, &infoBits)
        let infoBitsValue: UInt32? = infoStatus == kIOReturnSuccess ? infoBits : nil

        let builtIn = propertyBool(service: service, key: "Built-In") || propertyBool(service: service, key: "Internal")
        let className = ioObjectClassName(service: service)
        let isRootHub = className.localizedCaseInsensitiveContains("roothub")
        let registryExternal = !builtIn && !isRootHub

        let isExternal: Bool
        if let infoBitsValue {
            let connectedMask = UInt32(kUSBInformationDeviceIsConnectedMask.rawValue)
            let internalMask = UInt32(kUSBInformationDeviceIsInternalMask.rawValue)
            let rootHubMask = UInt32(kUSBInformationDeviceIsRootHubMask.rawValue)

            let isConnected = (infoBitsValue & connectedMask) != 0
            let isInternal = (infoBitsValue & internalMask) != 0
            let isRootHubByInfoBits = (infoBitsValue & rootHubMask) != 0

            // Do not treat "captive" as a hard exclusion.
            // Dock downstream devices are frequently marked captive despite being external.
            if isInternal || isRootHubByInfoBits {
                isExternal = false
            } else if isConnected {
                isExternal = true
            } else {
                isExternal = registryExternal
            }
        } else {
            isExternal = registryExternal
        }

        let interfaceClasses = collectInterfaceClasses(service: service)
        let deviceClassRaw = propertyUInt8(service: service, key: "bDeviceClass")
        let riskClass = USBPolicy.classifyRisk(
            deviceClass: deviceClassRaw,
            interfaceClasses: interfaceClasses,
            productName: displayName
        )

        let overrideAllowed = riskOverrides[stableID] ?? false
        let isBlocked = USBPolicy.isBlocked(riskClass: riskClass, overrideAllowed: overrideAllowed)
        let blockReason = USBPolicy.blockReason(for: riskClass, isBlocked: isBlocked)

        return USBDeviceRecord(
            deviceID: stableID,
            displayName: displayName,
            vendorID: vendorID,
            productID: productID,
            serial: serial,
            locationID: locationID,
            isExternal: isExternal,
            riskClass: riskClass,
            isBlocked: isBlocked,
            blockReason: blockReason
        )
    }

    private func pruneInactiveStateLocked(validDeviceIDs: Set<String>) {
        inactiveDeviceIDs = inactiveDeviceIDs.intersection(validDeviceIDs)
        riskOverrides = riskOverrides.filter { validDeviceIDs.contains($0.key) }
    }

    private func propertyString(service: io_service_t, key: String) -> String? {
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }

        if let stringValue = value as? String {
            return stringValue
        }

        return nil
    }

    private func propertyBool(service: io_service_t, key: String) -> Bool {
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return false
        }

        if let boolValue = value as? Bool {
            return boolValue
        }

        if let numberValue = value as? NSNumber {
            return numberValue.boolValue
        }

        return false
    }

    private func propertyUInt16(service: io_service_t, key: String) -> UInt16 {
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return 0
        }

        if let numberValue = value as? NSNumber {
            return numberValue.uint16Value
        }

        return 0
    }

    private func propertyUInt32(service: io_service_t, key: String) -> UInt32 {
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return 0
        }

        if let numberValue = value as? NSNumber {
            return numberValue.uint32Value
        }

        return 0
    }

    private func propertyUInt8(service: io_service_t, key: String) -> UInt8? {
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }

        if let numberValue = value as? NSNumber {
            return numberValue.uint8Value
        }

        return nil
    }

    private func resolveIdentity(for service: io_service_t) -> ResolvedIdentity {
        var vendorID: UInt16 = 0
        var productID: UInt16 = 0
        var serial = ""
        var locationID: UInt32 = 0
        var displayName = ""
        var vendorName = ""

        var current: io_registry_entry_t = service
        var ownsCurrent = false

        for _ in 0..<8 {
            if vendorID == 0 {
                vendorID = propertyUInt16(service: current, key: "idVendor")
            }
            if productID == 0 {
                productID = propertyUInt16(service: current, key: "idProduct")
            }
            if serial.isEmpty {
                serial = firstNonEmptyString(service: current, keys: ["USB Serial Number", "kUSBSerialNumberString"]) ?? ""
            }
            if locationID == 0 {
                locationID = propertyUInt32(service: current, key: "locationID")
            }
            if displayName.isEmpty {
                displayName = firstNonEmptyString(
                    service: current,
                    keys: ["USB Product Name", "kUSBProductString", "product-string", "IOName"]
                ) ?? ""
            }
            if vendorName.isEmpty {
                vendorName = firstNonEmptyString(
                    service: current,
                    keys: ["USB Vendor Name", "kUSBVendorString", "vendor-string"]
                ) ?? ""
            }

            let hasCoreIdentity = vendorID != 0 || productID != 0 || locationID != 0 || !displayName.isEmpty
            if hasCoreIdentity {
                break
            }

            var parent: io_registry_entry_t = 0
            let parentStatus = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            if parentStatus != kIOReturnSuccess || parent == IO_OBJECT_NULL {
                break
            }

            if ownsCurrent {
                IOObjectRelease(current)
            }
            current = parent
            ownsCurrent = true
        }

        if ownsCurrent {
            IOObjectRelease(current)
        }

        if displayName.isEmpty {
            if !vendorName.isEmpty, vendorID != 0 || productID != 0 {
                displayName = String(format: "%@ %04x:%04x", vendorName, vendorID, productID)
            } else if vendorID != 0 || productID != 0 {
                displayName = String(format: "USB Device %04x:%04x", vendorID, productID)
            } else {
                displayName = "USB Device"
            }
        }

        return ResolvedIdentity(
            vendorID: vendorID,
            productID: productID,
            serial: serial,
            locationID: locationID,
            displayName: displayName
        )
    }

    private func firstNonEmptyString(service: io_service_t, keys: [String]) -> String? {
        for key in keys {
            if let value = propertyString(service: service, key: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func collectInterfaceClasses(service: io_service_t) -> Set<UInt8> {
        var classes = Set<UInt8>()

        func walk(entry: io_registry_entry_t, depth: Int) {
            guard depth < 6 else {
                return
            }

            if let interfaceClass = propertyUInt8(service: entry, key: "bInterfaceClass") {
                classes.insert(interfaceClass)
            }

            var iterator: io_iterator_t = 0
            if IORegistryEntryGetChildIterator(entry, kIOServicePlane, &iterator) != kIOReturnSuccess {
                return
            }

            defer { IOObjectRelease(iterator) }

            var child = IOIteratorNext(iterator)
            while child != 0 {
                walk(entry: child, depth: depth + 1)
                IOObjectRelease(child)
                child = IOIteratorNext(iterator)
            }
        }

        walk(entry: service, depth: 0)
        return classes
    }

    private func ioObjectClassName(service: io_service_t) -> String {
        guard let className = IOObjectCopyClass(service)?.takeRetainedValue() as String? else {
            return ""
        }
        return className
    }

    private func ioKitErrorDescription(_ status: kern_return_t) -> String {
        if let cString = mach_error_string(status) {
            return String(cString: cString)
        }
        return "IOKit error \(status)"
    }

    private func mapIOKitStatus(_ status: kern_return_t) -> USBToggleErrorCode {
        if status == kIOReturnNoDevice {
            return .noDevice
        }

        if status == kIOReturnNotPermitted {
            return .notPermitted
        }

        if status == kIOReturnSuccess {
            return .none
        }

        return .ioKitError
    }
}
