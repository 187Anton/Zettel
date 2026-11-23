import AppKit

/// Owns the menu bar icon and attaches the status menu to it. While a timer runs,
/// its remaining time can be shown next to the icon (setting).
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    let statusMenu: StatusMenu
    private let timerCenter: TimerCenter?
    private let showsTimer: () -> Bool
    private var observers: [NSObjectProtocol] = []

    init(
        launchAtLogin: LaunchAtLoginController,
        actions: StatusMenuActions,
        showWindowShortcut: KeyCombo?,
        timerCenter: TimerCenter? = nil,
        showsTimer: @escaping () -> Bool = { true }
    ) {
        statusMenu = StatusMenu(launchAtLogin: launchAtLogin, actions: actions, showWindowShortcut: showWindowShortcut)
        statusMenu.timerCenter = timerCenter
        self.timerCenter = timerCenter
        self.showsTimer = showsTimer
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.behavior = .removalAllowed

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "note.text", accessibilityDescription: Strings.appName)
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.toolTip = Strings.appName
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }
        statusItem.menu = statusMenu.menu

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: TimerCenter.didChange, object: timerCenter, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateTitle() }
        })
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateTitle() }
        })
        updateTitle()
    }

    /// Text next to the icon: remaining time of the most urgent timer, or nothing.
    var title: String {
        guard showsTimer(), let timerCenter, let timer = timerCenter.primaryTimer else { return "" }
        let text = TimerFormat.menuBar(timer, at: timerCenter.date)
        return timer.isPaused ? "⏸ " + text : text
    }

    private func updateTitle() {
        guard let button = statusItem.button else { return }
        let title = self.title.isEmpty ? "" : " " + self.title
        if button.title != title { button.title = title }
    }
}
