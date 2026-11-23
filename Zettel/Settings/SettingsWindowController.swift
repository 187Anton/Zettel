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
    var currentWindow: NSWindow? { window }

    func show() {
        launchAtLogin.refresh()

        if window == nil {
            let tabs = NSTabViewController()
            tabs.tabStyle = .toolbar
            tabs.transitionOptions = [.allowUserInteraction]
            for tab in SettingsTab.allCases {
                let hosting = NSHostingController(rootView: tab.view(
                    launchAtLogin: launchAtLogin, backups: backups, onRestore: onRestore
                ))
                hosting.sizingOptions = [.preferredContentSize]
                hosting.title = tab.title
                let item = NSTabViewItem(viewController: hosting)
                item.label = tab.title
                item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
                tabs.addTabViewItem(item)
            }
            let window = NSWindow(contentViewController: tabs)
            window.title = Strings.Settings.windowTitle
            window.styleMask = [.titled, .closable]
            window.toolbarStyle = .preference
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
