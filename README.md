# USB Monitor

`usb-monitor` is a macOS menu bar utility for inspecting external USB devices and toggling them through a privileged helper.

The current Xcode targets and bundle names still use the original `USBToggle` project naming. This repository keeps that code structure intact, but strips generated build output and local signing metadata before publication.

## What it includes

- A menu bar app built with SwiftUI
- A privileged helper/launch daemon exposed over XPC
- Shared DTOs and policy code for USB device classification
- Unit test targets for shared models and protocol constants

## Notes

- The helper is intended for signed local builds on macOS 13+.
- Automatic signing is left unconfigured in source control; set your own team in Xcode before testing helper installation.
- Regenerate the Xcode project with `xcodegen generate` after editing `project.yml`.
