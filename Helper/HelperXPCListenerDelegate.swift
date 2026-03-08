import Foundation
import os
import USBToggleShared

final class HelperXPCListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service: USBToggleHelperService
    private let logger = Logger(subsystem: USBToggleConstants.logSubsystem, category: "listener")

    init(service: USBToggleHelperService) {
        self.service = service
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = XPCInterfaceFactory.helperInterface()
        newConnection.exportedObject = service
        newConnection.resume()
        logger.log("Accepted new XPC connection")
        return true
    }
}
