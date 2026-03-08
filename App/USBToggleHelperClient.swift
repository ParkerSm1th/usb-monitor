import Foundation
import os
import USBToggleShared

enum USBToggleClientError: LocalizedError {
    case helperUnavailable(String)
    case timeout
    case protocolMismatch(found: Int)

    var errorDescription: String? {
        switch self {
        case let .helperUnavailable(message):
            return message
        case .timeout:
            return "Timed out waiting for helper response. The privileged helper may be blocked by code-signing policy or not running."
        case let .protocolMismatch(found):
            return "Protocol mismatch. Helper protocol version \(found), expected \(USBToggleConstants.protocolVersion)."
        }
    }
}

final class USBToggleHelperClient {
    private let logger = Logger(subsystem: USBToggleConstants.logSubsystem, category: "client")
    private let callbackQueue = DispatchQueue(label: "com.parker.usbtoggle.client.callback")

    func listDevices(timeout: TimeInterval = 4.0, completion: @escaping (Result<[USBDeviceSnapshotDTO], Error>) -> Void) {
        withProxy(timeout: timeout, completion: completion) { proxy, finish in
            proxy.listDevices { devices, helperError in
                if let helperError, !helperError.isEmpty {
                    finish(.failure(USBToggleClientError.helperUnavailable(helperError)))
                } else {
                    finish(.success(devices))
                }
            }
        }
    }

    func setDeviceActive(deviceID: String, active: Bool, timeout: TimeInterval = 4.0, completion: @escaping (Result<ToggleResultDTO, Error>) -> Void) {
        withProxy(timeout: timeout, completion: completion) { proxy, finish in
            proxy.setDeviceActive(deviceID: deviceID, active: active) { result in
                finish(.success(result))
            }
        }
    }

    func setRiskOverride(deviceID: String, allowed: Bool, timeout: TimeInterval = 4.0, completion: @escaping (Result<Bool, Error>) -> Void) {
        withProxy(timeout: timeout, completion: completion) { proxy, finish in
            proxy.setRiskOverride(deviceID: deviceID, allowed: allowed) { success, errorMessage in
                if success {
                    finish(.success(true))
                } else {
                    finish(.failure(USBToggleClientError.helperUnavailable(errorMessage ?? "Unknown helper error")))
                }
            }
        }
    }

    private func withProxy<T>(
        timeout: TimeInterval,
        completion: @escaping (Result<T, Error>) -> Void,
        call: @escaping (_ proxy: USBToggleHelperXPC, _ finish: @escaping (Result<T, Error>) -> Void) -> Void
    ) {
        let connection = NSXPCConnection(machServiceName: USBToggleConstants.helperMachServiceName, options: .privileged)
        connection.remoteObjectInterface = XPCInterfaceFactory.helperInterface()

        let gate = CompletionGate<T>(connection: connection, callbackQueue: callbackQueue, completion: completion)

        connection.interruptionHandler = {
            gate.finish(.failure(USBToggleClientError.helperUnavailable(self.helperConnectionFailureHint(prefix: "Helper XPC connection interrupted"))))
        }

        connection.invalidationHandler = {
            gate.finish(.failure(USBToggleClientError.helperUnavailable(self.helperConnectionFailureHint(prefix: "Helper XPC connection invalidated"))))
        }

        connection.resume()

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            gate.finish(.failure(USBToggleClientError.helperUnavailable(self.helperConnectionFailureHint(prefix: "Helper remote proxy failed: \(error.localizedDescription)"))))
        }) as? USBToggleHelperXPC else {
            gate.finish(.failure(USBToggleClientError.helperUnavailable(self.helperConnectionFailureHint(prefix: "Failed to create helper proxy"))))
            return
        }

        callbackQueue.asyncAfter(deadline: .now() + timeout) {
            gate.finish(.failure(USBToggleClientError.timeout))
        }

        proxy.protocolVersion { version in
            guard version == USBToggleConstants.protocolVersion else {
                gate.finish(.failure(USBToggleClientError.protocolMismatch(found: version)))
                return
            }

            call(proxy) { result in
                gate.finish(result)
            }
        }
    }
}

extension USBToggleHelperClient {
    fileprivate func helperConnectionFailureHint(prefix: String) -> String {
        "\(prefix). Verify USB Toggle is signed (not ad-hoc), installed/ran via Xcode with signing enabled, and that the privileged helper is approved in System Settings > Login Items."
    }
}

private final class CompletionGate<T> {
    private let connection: NSXPCConnection
    private let callbackQueue: DispatchQueue
    private let completion: (Result<T, Error>) -> Void

    private var isFinished = false

    init(connection: NSXPCConnection, callbackQueue: DispatchQueue, completion: @escaping (Result<T, Error>) -> Void) {
        self.connection = connection
        self.callbackQueue = callbackQueue
        self.completion = completion
    }

    func finish(_ result: Result<T, Error>) {
        callbackQueue.async {
            guard !self.isFinished else {
                return
            }

            self.isFinished = true
            self.connection.invalidationHandler = nil
            self.connection.interruptionHandler = nil
            self.connection.invalidate()

            DispatchQueue.main.async {
                self.completion(result)
            }
        }
    }
}
