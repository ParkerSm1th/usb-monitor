import Foundation
import os
import USBToggleShared

let logger = Logger(subsystem: USBToggleConstants.logSubsystem, category: "main")
logger.log("Starting USBToggle helper")

let deviceManager = USBDeviceManager()
let service = USBToggleHelperService(manager: deviceManager)
let delegate = HelperXPCListenerDelegate(service: service)

let listener = NSXPCListener(machServiceName: USBToggleConstants.helperMachServiceName)
listener.delegate = delegate
listener.resume()

logger.log("USBToggle helper listening on \(USBToggleConstants.helperMachServiceName, privacy: .public)")
RunLoop.main.run()
