import Foundation
import AppKit
import Security
import ServiceManagement
import USBToggleShared

enum HelperServiceStatus: Equatable {
    case enabled
    case notRegistered
    case requiresApproval
    case notFound
    case runtimeError(String)
    case unknown

    var isEnabled: Bool {
        self == .enabled
    }

    var guidanceText: String {
        switch self {
        case .enabled:
            return "Privileged helper is enabled."
        case .notRegistered:
            return "Privileged helper is not installed. Click Enable Privileged Helper."
        case .requiresApproval:
            return "Helper installed, but approval is required in System Settings > Login Items."
        case .notFound:
            return "Helper was not found in the app bundle packaging paths."
        case let .runtimeError(details):
            return "Helper is registered but not running correctly. \(details)"
        case .unknown:
            return "Helper status is unknown."
        }
    }
}

enum HelperInstallerError: LocalizedError {
    case authorizationFailed(OSStatus)
    case signingPreflightFailed(String)

    var errorDescription: String? {
        switch self {
        case let .authorizationFailed(status):
            if status == errAuthorizationCanceled {
                return "Administrator authentication was canceled."
            }
            return "Administrator authentication failed (\(status))."
        case let .signingPreflightFailed(message):
            return message
        }
    }
}

final class HelperInstaller {
    private var daemonService: SMAppService {
        SMAppService.daemon(plistName: USBToggleConstants.helperLaunchDaemonPlistName)
    }

    func currentStatus() -> HelperServiceStatus {
        let status = mapStatus(daemonService.status)
        guard case .enabled = status else {
            return status
        }

        if !isAppInstalledInApplications() {
            return .runtimeError("USB Toggle is running outside /Applications. Move the app to /Applications, launch it from there, then enable the helper again.")
        }

        if let runtimeIssue = runtimeIssueFromLaunchctl() {
            return .runtimeError(runtimeIssue)
        }

        return status
    }

    func registerHelper() throws -> HelperServiceStatus {
        // Clean up stale registrations first; this is safe to ignore if nothing is registered.
        if daemonService.status != .notRegistered {
            try? daemonService.unregister()
        }

        if let preflightIssue = signingPreflightIssue() {
            throw HelperInstallerError.signingPreflightFailed(preflightIssue)
        }

        try requestAdministratorAuthorization()

        try daemonService.register()
        return currentStatus()
    }

    func openApprovalSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func openApplicationsFolder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: "/Applications")
    }

    func revealCurrentAppInFinder() {
        let appURL = URL(fileURLWithPath: Bundle.main.bundlePath)
        NSWorkspace.shared.activateFileViewerSelecting([appURL])
    }

    func isAppInstalledInApplications() -> Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/")
    }

    private func mapStatus(_ status: SMAppService.Status) -> HelperServiceStatus {
        switch status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .notRegistered
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .unknown
        }
    }

    private func requestAdministratorAuthorization() throws {
        var authRef: AuthorizationRef?
        let createStatus = AuthorizationCreate(nil, nil, [], &authRef)
        guard createStatus == errAuthorizationSuccess, let authRef else {
            throw HelperInstallerError.authorizationFailed(createStatus)
        }
        defer {
            AuthorizationFree(authRef, [])
        }

        let flags: AuthorizationFlags = [.interactionAllowed, .extendRights, .preAuthorize]
        let rightName = "system.privilege.admin"
        let status: OSStatus = rightName.withCString { rightCString in
            var item = AuthorizationItem(name: rightCString, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { itemPtr in
                var rights = AuthorizationRights(count: 1, items: itemPtr)
                return AuthorizationCopyRights(authRef, &rights, nil, flags, nil)
            }
        }

        guard status == errAuthorizationSuccess else {
            throw HelperInstallerError.authorizationFailed(status)
        }
    }

    private func runtimeIssueFromLaunchctl() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "system/com.parker.usbtoggle.helper"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""

        if text.contains("job state = spawn failed") {
            if let constraintIssue = recentLaunchConstraintIssue() {
                return constraintIssue
            }
            if let exitLine = text.split(separator: "\n").first(where: { $0.contains("last exit code") }) {
                return String(exitLine).trimmingCharacters(in: .whitespaces)
            }
            return "launchd reports spawn failed."
        }

        if text.contains("service inactive") {
            return "launchd reports the helper is inactive."
        }

        return nil
    }

    private func recentLaunchConstraintIssue() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "show",
            "--style", "compact",
            "--last", "10m",
            "--predicate",
            "eventMessage CONTAINS[c] \"com.parker.usbtoggle.helper\" && eventMessage CONTAINS[c] \"Constraint not matched\""
        ]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""

        guard text.contains("Constraint not matched") else {
            return nil
        }

        if !isAppInstalledInApplications() {
            return "launchd rejected helper launch (Constraint not matched). Run USB Toggle from /Applications, then re-enable the helper."
        }

        return "launchd rejected helper launch due code-signing launch constraints (Constraint not matched). Rebuild with valid signing and re-enable the helper."
    }

    private func signingPreflightIssue() -> String? {
        let appPath = Bundle.main.bundlePath
        let helperPath = (appPath as NSString).appendingPathComponent("Contents/Library/HelperTools/USBToggleHelper")

        if !isAppInstalledInApplications() {
            return "USB Toggle must run from /Applications for privileged daemon launch constraints. Move the app to /Applications and launch it from there, then enable the helper again."
        }

        guard FileManager.default.fileExists(atPath: helperPath) else {
            return "Helper binary is missing from app bundle at \(helperPath). Rebuild the app."
        }

        if isAdHocSigned(path: appPath) {
            return "App is ad-hoc signed. In Xcode, set a real signing team and certificate (Apple Development or Developer ID Application) for USBToggleApp."
        }

        if isAdHocSigned(path: helperPath) {
            return "Helper is ad-hoc signed. In Xcode, set a real signing team and certificate (Apple Development or Developer ID Application) for USBToggleHelper, then rebuild."
        }

        if !isCodeSignatureValid(path: appPath) {
            return "App signature failed validation. Rebuild with a valid signing identity, then re-run."
        }

        if !isCodeSignatureValid(path: helperPath) {
            return "Helper signature failed validation. Rebuild with a valid signing identity, then re-run."
        }

        return nil
    }

    private func isAdHocSigned(path: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dv", path]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
        } catch {
            return true
        }

        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.localizedCaseInsensitiveContains("Signature=adhoc")
    }

    private func isCodeSignatureValid(path: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--deep", "--strict", path]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
        } catch {
            return false
        }

        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
