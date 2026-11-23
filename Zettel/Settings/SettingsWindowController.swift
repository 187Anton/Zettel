import AppKit
import SwiftUI

/// Shows the SwiftUI settings in a regular window. The window is created on
/// demand and released when closed, so it costs no memory while hidden.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let launchAtLogin: LaunchAtLoginController
    private let backups: BackupManager?
    private let onRestore: () -> Void
    private var window: NSWindow?

    init(launchAtLogin: LaunchAtLoginController, backups: BackupManager? = nil, onRestore: @escaping () -> Void = {}) {
        self.launchAtLogin = launchAtLogin
        self.backups = backups
        self.onRestore = onRestore
        super.init()
    }

    var isShown: Bool { window != nil }

    func show() {
        launchAtLogin.refresh()

        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(
                launchAtLogin: launchAtLogin, backups: backups, onRestore: onRestore
            ))
            let window = NSWindow(contentViewController: hosting)
            window.title = Strings.Settings.windowTitle
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }

        // Agent apps are never active by default; activate so the window comes to the front.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window = nil
    }
}
