import Carbon.HIToolbox
import CoreGraphics

/// Commands the note window reacts to.
enum PanelCommand: Equatable, Sendable {
    case togglePin
    case close
}

/// Maps key presses inside the note window to commands. AppKit-free for testing.
enum PanelShortcuts {
    static func command(keyCode: UInt16, characters: String?, modifiers: KeyModifiers) -> PanelCommand? {
        if Int(keyCode) == kVK_Escape, modifiers.isEmpty {
            return .close
        }
        guard modifiers == .command, let key = characters?.lowercased() else { return nil }
        switch key {
        case "p": return .togglePin
        case "w": return .close
        default: return nil
        }
    }
}

/// Decides what the global hotkey does depending on the window state.
enum PanelVisibility {
    enum Action: Equatable {
        /// Show (or bring back focus to) the window.
        case show
        case hide
    }

    /// Hotkey hides the window only if it is visible *and* focused. A visible but
    /// unfocused window (pinned, user working elsewhere) gets the focus instead.
    static func hotKeyAction(isVisible: Bool, isKey: Bool) -> Action {
        isVisible && isKey ? .hide : .show
    }

    /// Without pinning, the window hides as soon as it loses focus.
    static func shouldHideOnFocusLoss(isPinned: Bool) -> Bool {
        !isPinned
    }
}

/// Computes where the note window appears. Works with screen `visibleFrame`s
/// (excluding menu bar and Dock) in AppKit's global coordinates.
enum PanelFramePlacement {
    static let defaultSize = CGSize(width: 440, height: 520)
    static let minimumSize = CGSize(width: 280, height: 200)
    /// A saved frame must overlap a screen at least this much to be reused.
    static let minimumVisibleOverlap = CGSize(width: 120, height: 80)

    /// Saved frame if still usable, otherwise a default frame on `preferredScreen`.
    static func frame(saved: CGRect?, screens: [CGRect], preferredScreen: CGRect) -> CGRect {
        if let saved, let restored = restoredFrame(saved: saved, screens: screens) {
            return restored
        }
        return defaultFrame(on: preferredScreen)
    }

    /// Fits the saved frame onto the screen it overlaps most, or `nil` if it is
    /// (nearly) off-screen, e.g. because that display was disconnected.
    static func restoredFrame(saved: CGRect, screens: [CGRect]) -> CGRect? {
        let candidates = screens.map { screen in (screen, saved.intersection(screen)) }
        guard let (screen, overlap) = candidates.max(by: { area($0.1) < area($1.1) }),
              !overlap.isNull,
              overlap.width >= min(minimumVisibleOverlap.width, saved.width),
              overlap.height >= min(minimumVisibleOverlap.height, saved.height)
        else { return nil }
        return clamp(saved, into: screen)
    }

    /// Centered horizontally, slightly above the vertical center.
    static func defaultFrame(on screen: CGRect) -> CGRect {
        let size = CGSize(
            width: min(defaultSize.width, screen.width),
            height: min(defaultSize.height, screen.height)
        )
        let origin = CGPoint(
            x: screen.midX - size.width / 2,
            y: screen.midY - size.height / 2 + screen.height * 0.1
        )
        return clamp(CGRect(origin: origin, size: size), into: screen)
    }

    /// Enforces the minimum size, shrinks to the screen and moves the frame fully onto it.
    static func clamp(_ frame: CGRect, into screen: CGRect) -> CGRect {
        let width = min(max(frame.width, minimumSize.width), screen.width)
        let height = min(max(frame.height, minimumSize.height), screen.height)
        let x = min(max(frame.minX, screen.minX), screen.maxX - width)
        let y = min(max(frame.minY, screen.minY), screen.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }
}
