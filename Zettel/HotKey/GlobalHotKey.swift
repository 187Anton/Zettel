import Carbon.HIToolbox

/// A system-wide hotkey registered via Carbon's `RegisterEventHotKey`.
///
/// Needs no Accessibility permission and costs nothing while idle: the system
/// delivers an event only when the shortcut is pressed. Unregisters on deinit.
@MainActor
final class GlobalHotKey {
    enum RegistrationError: Error, Equatable {
        case handlerInstallFailed(OSStatus)
        case registerFailed(OSStatus)
    }

    /// Four-char code 'ZTTL' identifying Zettel's hotkeys.
    static let signature: OSType = 0x5A54_544C
    private static var nextID: UInt32 = 1

    let combo: KeyCombo
    let hotKeyID: EventHotKeyID
    private let action: @MainActor () -> Void

    // Accessed in deinit, which is nonisolated. Only ever touched on the main thread.
    nonisolated(unsafe) private var hotKeyRef: EventHotKeyRef?
    nonisolated(unsafe) private var handlerRef: EventHandlerRef?

    init(combo: KeyCombo, action: @escaping @MainActor () -> Void) throws {
        self.combo = combo
        self.action = action
        self.hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.nextID)
        Self.nextID += 1

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            globalHotKeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard installStatus == noErr else {
            throw RegistrationError.handlerInstallFailed(installStatus)
        }

        let registerStatus = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers.carbonFlags,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            // deinit removes the already installed handler.
            throw RegistrationError.registerFailed(registerStatus)
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    var isRegistered: Bool { hotKeyRef != nil }

    /// Runs the action if the event belongs to this hotkey.
    @discardableResult
    func handle(_ pressedID: EventHotKeyID) -> Bool {
        guard pressedID.signature == hotKeyID.signature, pressedID.id == hotKeyID.id else {
            return false
        }
        action()
        return true
    }
}

/// C callback for Carbon. Carbon dispatches hotkey events on the main thread.
private func globalHotKeyEventHandler(
    _: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var pressedID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &pressedID
    )
    guard status == noErr else { return status }

    // Raw pointers are not Sendable; it is only dereferenced on the main thread.
    nonisolated(unsafe) let hotKeyPointer = userData
    let handled = MainActor.assumeIsolated {
        Unmanaged<GlobalHotKey>.fromOpaque(hotKeyPointer).takeUnretainedValue().handle(pressedID)
    }
    return handled ? noErr : OSStatus(eventNotHandledErr)
}
