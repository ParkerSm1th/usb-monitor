import SwiftUI
import AppKit
import USBToggleShared

struct AppMenuView: View {
    @ObservedObject var viewModel: USBToggleViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            helperStatusSection

            Divider()

            if viewModel.devices.isEmpty {
                Text("No external USB devices detected")
                    .foregroundStyle(.secondary)
            } else {
                devicesSection
            }

            Divider()

            footerSection
        }
        .padding(12)
        .frame(minWidth: 380)
        .alert("USB Toggle", isPresented: $viewModel.isShowingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage ?? "Unknown error")
        }
    }

    private var helperStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Helper Status")
                .font(.headline)

            Text(viewModel.helperStatus.guidanceText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !viewModel.isRunningFromApplications {
                Text("Move USB Toggle to /Applications before enabling the privileged helper.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button("Open /Applications") {
                        viewModel.openApplicationsFolder()
                    }

                    Button("Reveal Current App") {
                        viewModel.revealCurrentAppInFinder()
                    }
                }
            }

            if !viewModel.helperStatus.isEnabled {
                HStack(spacing: 8) {
                    Button("Enable Privileged Helper") {
                        viewModel.enableHelper()
                    }
                    .disabled(!viewModel.isRunningFromApplications)

                    if viewModel.helperStatus == .requiresApproval {
                        Button("Open Settings") {
                            viewModel.openApprovalSettings()
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Button("Reload Privileged Helper") {
                        viewModel.enableHelper()
                    }

                    Button("Open Settings") {
                        viewModel.openApprovalSettings()
                    }
                }
            }
        }
    }

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Devices")
                .font(.headline)

            ForEach(viewModel.devices, id: \.deviceID) { device in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(device.displayName)
                            .font(.body)
                        Spacer()
                        Text(device.isActive ? "Active" : "Inactive")
                            .font(.caption)
                            .foregroundStyle(device.isActive ? .green : .orange)
                    }

                    Text(String(format: "VID:PID %04x:%04x • ID %@", Int(device.vendorID), Int(device.productID), shortID(device.deviceID)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if device.isBlocked {
                        Text(device.blockReason)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button(viewModel.hasOverride(for: device.deviceID) ? "Remove Override" : "Allow Override") {
                            if viewModel.hasOverride(for: device.deviceID) {
                                viewModel.clearRiskOverride(for: device)
                            } else {
                                viewModel.allowRiskOverride(for: device)
                            }
                        }
                    }

                    Button(device.isActive ? "Deactivate" : "Reactivate") {
                        viewModel.toggle(device: device)
                    }
                    .disabled(device.isBlocked || viewModel.togglingDeviceIDs.contains(device.deviceID))
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var footerSection: some View {
        HStack(spacing: 8) {
            Button("Refresh") {
                viewModel.refresh()
            }
            .disabled(viewModel.isRefreshing)

            Button("Show Last Error") {
                viewModel.showLastError()
            }
            .disabled(viewModel.lastError == nil)

            Spacer()

            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
    }

    private func shortID(_ fullID: String) -> String {
        if fullID.count <= 16 {
            return fullID
        }
        return String(fullID.prefix(16)) + "…"
    }
}
