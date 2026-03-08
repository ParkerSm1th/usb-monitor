import Foundation
import AppKit
import os
import USBToggleShared

@MainActor
final class USBToggleViewModel: ObservableObject {
    @Published private(set) var devices: [USBDeviceSnapshotDTO] = []
    @Published private(set) var helperStatus: HelperServiceStatus = .unknown
    @Published private(set) var isRunningFromApplications = true
    @Published private(set) var isRefreshing = false
    @Published private(set) var togglingDeviceIDs = Set<String>()
    @Published var isShowingErrorAlert = false
    @Published var alertMessage: String?
    @Published var lastError: String?

    private let logger = Logger(subsystem: USBToggleConstants.logSubsystem, category: "view-model")

    private let helperInstaller = HelperInstaller()
    private let helperClient = USBToggleHelperClient()
    private let defaults = UserDefaults.standard
    private let overridesDefaultsKey = "com.parker.usbtoggle.risk-overrides"

    private var loadedOnce = false

    func refreshIfNeeded() {
        guard !loadedOnce else {
            return
        }
        loadedOnce = true
        refresh()
    }

    func refresh() {
        isRunningFromApplications = helperInstaller.isAppInstalledInApplications()
        helperStatus = helperInstaller.currentStatus()

        guard helperStatus.isEnabled else {
            devices = []
            return
        }

        isRefreshing = true
        helperClient.listDevices { [weak self] result in
            guard let self else {
                return
            }

            self.isRefreshing = false

            switch result {
            case let .success(devices):
                self.devices = devices
                self.syncRiskOverrides()
            case let .failure(error):
                self.recordError("Failed to list USB devices: \(error.localizedDescription)")
            }
        }
    }

    func enableHelper() {
        do {
            helperStatus = try helperInstaller.registerHelper()
            if case let .runtimeError(details) = helperStatus {
                let isApplicationsIssue = details.localizedCaseInsensitiveContains("/Applications")
                recordError(
                    "Helper registration completed but helper failed at runtime: \(details)",
                    includeSettingsAction: true,
                    includeApplicationsAction: isApplicationsIssue,
                    includeRevealCurrentAppAction: isApplicationsIssue
                )
            }
            refresh()
        } catch {
            let message = "Failed to register helper: \(error.localizedDescription)"
            let shouldOfferSettings = message.localizedCaseInsensitiveContains("operation not permitted")
                || message.localizedCaseInsensitiveContains("approval")
            let isApplicationsIssue = message.localizedCaseInsensitiveContains("/Applications")
            recordError(
                message,
                includeSettingsAction: shouldOfferSettings,
                includeApplicationsAction: isApplicationsIssue,
                includeRevealCurrentAppAction: isApplicationsIssue
            )
        }
    }

    func openApprovalSettings() {
        helperInstaller.openApprovalSettings()
    }

    func openApplicationsFolder() {
        helperInstaller.openApplicationsFolder()
    }

    func revealCurrentAppInFinder() {
        helperInstaller.revealCurrentAppInFinder()
    }

    func toggle(device: USBDeviceSnapshotDTO) {
        guard !device.isBlocked else {
            recordError("\(device.displayName) is blocked by policy: \(device.blockReason)")
            return
        }

        togglingDeviceIDs.insert(device.deviceID)

        helperClient.setDeviceActive(deviceID: device.deviceID, active: !device.isActive) { [weak self] result in
            guard let self else {
                return
            }

            self.togglingDeviceIDs.remove(device.deviceID)

            switch result {
            case let .success(toggleResult):
                if toggleResult.success {
                    self.refresh()
                } else {
                    let message = toggleResult.errorMessage.isEmpty
                        ? "Device toggle failed with code \(toggleResult.errorCode)"
                        : toggleResult.errorMessage
                    self.recordError(message)
                    self.refresh()
                }
            case let .failure(error):
                self.recordError("Toggle request failed: \(error.localizedDescription)")
            }
        }
    }

    func allowRiskOverride(for device: USBDeviceSnapshotDTO) {
        setOverrideAllowed(deviceID: device.deviceID, allowed: true)

        helperClient.setRiskOverride(deviceID: device.deviceID, allowed: true) { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .success:
                self.refresh()
            case let .failure(error):
                self.recordError("Failed to apply override: \(error.localizedDescription)")
            }
        }
    }

    func clearRiskOverride(for device: USBDeviceSnapshotDTO) {
        setOverrideAllowed(deviceID: device.deviceID, allowed: false)

        helperClient.setRiskOverride(deviceID: device.deviceID, allowed: false) { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .success:
                self.refresh()
            case let .failure(error):
                self.recordError("Failed to clear override: \(error.localizedDescription)")
            }
        }
    }

    func showLastError() {
        guard let lastError else {
            return
        }

        alertMessage = lastError
        isShowingErrorAlert = true
    }

    func hasOverride(for deviceID: String) -> Bool {
        loadOverrides()[deviceID] ?? false
    }

    private func syncRiskOverrides() {
        let overrides = loadOverrides()
        for (deviceID, allowed) in overrides where allowed {
            helperClient.setRiskOverride(deviceID: deviceID, allowed: true) { [weak self] result in
                if case let .failure(error) = result {
                    self?.logger.error("Failed to sync risk override for \(deviceID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func setOverrideAllowed(deviceID: String, allowed: Bool) {
        var overrides = loadOverrides()
        overrides[deviceID] = allowed
        defaults.set(overrides, forKey: overridesDefaultsKey)
    }

    private func loadOverrides() -> [String: Bool] {
        if let value = defaults.dictionary(forKey: overridesDefaultsKey) as? [String: Bool] {
            return value
        }
        return [:]
    }

    private func recordError(
        _ message: String,
        includeSettingsAction: Bool = false,
        includeApplicationsAction: Bool = false,
        includeRevealCurrentAppAction: Bool = false
    ) {
        logger.error("\(message, privacy: .public)")
        lastError = message
        alertMessage = message
        isShowingErrorAlert = true
        presentNativeErrorDialog(
            message: message,
            includeSettingsAction: includeSettingsAction,
            includeApplicationsAction: includeApplicationsAction,
            includeRevealCurrentAppAction: includeRevealCurrentAppAction
        )
    }

    private func presentNativeErrorDialog(
        message: String,
        includeSettingsAction: Bool,
        includeApplicationsAction: Bool,
        includeRevealCurrentAppAction: Bool
    ) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "USB Toggle"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")

        var actionHandlers: [() -> Void] = []

        if includeApplicationsAction {
            alert.addButton(withTitle: "Open /Applications")
            actionHandlers.append { [helperInstaller] in
                helperInstaller.openApplicationsFolder()
            }
        }

        if includeRevealCurrentAppAction {
            alert.addButton(withTitle: "Reveal Current App")
            actionHandlers.append { [helperInstaller] in
                helperInstaller.revealCurrentAppInFinder()
            }
        }

        if includeSettingsAction {
            alert.addButton(withTitle: "Open Settings")
            actionHandlers.append { [helperInstaller] in
                helperInstaller.openApprovalSettings()
            }
        }

        let result = alert.runModal()
        let first = NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        let tappedIndex = Int(result.rawValue - first - 1)
        if tappedIndex >= 0, tappedIndex < actionHandlers.count {
            actionHandlers[tappedIndex]()
        }
    }
}
