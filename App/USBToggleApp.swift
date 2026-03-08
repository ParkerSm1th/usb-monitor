import SwiftUI

@main
struct USBToggleApp: App {
    @StateObject private var viewModel = USBToggleViewModel()

    var body: some Scene {
        MenuBarExtra("USB Toggle", systemImage: "externaldrive.connected.to.line.below") {
            AppMenuView(viewModel: viewModel)
                .onAppear {
                    viewModel.refreshIfNeeded()
                }
        }
        .menuBarExtraStyle(.window)
    }
}
