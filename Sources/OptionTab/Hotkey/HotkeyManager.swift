import AppKit
@preconcurrency import ApplicationServices
import Carbon

/// Manages a global keyboard shortcut using CGEvent tap.
/// Default shortcut: Option + Tab.
/// Configurable via UserDefaults.
final class HotkeyManager: @unchecked Sendable {
    // MARK: - Types

    enum SwitcherMode: Sendable {
        case allApps
        case currentApp
    }

    struct Shortcut: Codable, Equatable, Sendable {
        let keyCode: UInt32
        let modifierFlags: UInt32

        static let defaultShortcut = Shortcut(
            keyCode: UInt32(kVK_Tab),
            modifierFlags: UInt32(optionKey)
        )

        static let defaultCurrentAppShortcut = Shortcut(
            keyCode: UInt32(kVK_ANSI_Q),
            modifierFlags: UInt32(optionKey)
        )

        var displayString: String {
            var parts: [String] = []
            if modifierFlags & UInt32(cmdKey) != 0 { parts.append("\u{2318}") }    // ⌘
            if modifierFlags & UInt32(optionKey) != 0 { parts.append("\u{2325}") }  // ⌥
            if modifierFlags & UInt32(controlKey) != 0 { parts.append("\u{2303}") }  // ⌃
            if modifierFlags & UInt32(shiftKey) != 0 { parts.append("\u{21E7}") }    // ⇧

            let keyName = keyCodeToString(keyCode)
            parts.append(keyName)

            return parts.joined()
        }

        private func keyCodeToString(_ keyCode: UInt32) -> String {
            // Carbon key constants are Int; cast to UInt16 for lookup
            let key = UInt16(keyCode)
            switch key {
            case UInt16(kVK_Tab): return "Tab"
            case UInt16(kVK_Return): return "Return"
            case UInt16(kVK_Space): return "Space"
            case UInt16(kVK_Escape): return "Esc"
            case UInt16(kVK_Delete): return "Delete"
            case UInt16(kVK_ForwardDelete): return "FwdDel"
            case UInt16(kVK_LeftArrow): return "\u{2190}"   // ←
            case UInt16(kVK_RightArrow): return "\u{2192}"  // →
            case UInt16(kVK_UpArrow): return "\u{2191}"    // ↑
            case UInt16(kVK_DownArrow): return "\u{2193}"  // ↓
            case UInt16(kVK_ANSI_Quote): return "\""
            case UInt16(kVK_ANSI_Grave): return "`"
            default:
                if let char = keyCodeToChar(keyCode) { return String(char).uppercased() }
                return "Key\(keyCode)"
            }
        }

        private func keyCodeToChar(_ keyCode: UInt32) -> Character? {
            // Carbon kVK_ANSI_* constants are Int; cast to UInt16 for dictionary keys
            let mapping: [UInt16: Character] = [
                UInt16(kVK_ANSI_A): "a", UInt16(kVK_ANSI_B): "b", UInt16(kVK_ANSI_C): "c", UInt16(kVK_ANSI_D): "d",
                UInt16(kVK_ANSI_E): "e", UInt16(kVK_ANSI_F): "f", UInt16(kVK_ANSI_G): "g", UInt16(kVK_ANSI_H): "h",
                UInt16(kVK_ANSI_I): "i", UInt16(kVK_ANSI_J): "j", UInt16(kVK_ANSI_K): "k", UInt16(kVK_ANSI_L): "l",
                UInt16(kVK_ANSI_M): "m", UInt16(kVK_ANSI_N): "n", UInt16(kVK_ANSI_O): "o", UInt16(kVK_ANSI_P): "p",
                UInt16(kVK_ANSI_Q): "q", UInt16(kVK_ANSI_R): "r", UInt16(kVK_ANSI_S): "s", UInt16(kVK_ANSI_T): "t",
                UInt16(kVK_ANSI_U): "u", UInt16(kVK_ANSI_V): "v", UInt16(kVK_ANSI_W): "w", UInt16(kVK_ANSI_X): "x",
                UInt16(kVK_ANSI_Y): "y", UInt16(kVK_ANSI_Z): "z",
                UInt16(kVK_ANSI_0): "0", UInt16(kVK_ANSI_1): "1", UInt16(kVK_ANSI_2): "2", UInt16(kVK_ANSI_3): "3",
                UInt16(kVK_ANSI_4): "4", UInt16(kVK_ANSI_5): "5", UInt16(kVK_ANSI_6): "6", UInt16(kVK_ANSI_7): "7",
                UInt16(kVK_ANSI_8): "8", UInt16(kVK_ANSI_9): "9"
            ]
            return mapping[UInt16(keyCode)]
        }
    }

    // MARK: - Callbacks

    var onActivate: (@Sendable (SwitcherMode) -> Void)?
    var onCycle: (@Sendable (Bool) -> Void)?
    var onDeactivate: (@Sendable (WindowItem?) -> Void)?
    var onCancel: (@Sendable () -> Void)?

    // MARK: - Properties

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var shortcut: Shortcut
    private(set) var currentAppShortcut: Shortcut
    fileprivate var isActive = false
    fileprivate var currentMode: SwitcherMode = .allApps
    fileprivate var activeShortcut: Shortcut?
    fileprivate var modifierPressed = false

    private static let shortcutKey = "HotkeyManager.shortcut"
    private static let currentAppShortcutKey = "HotkeyManager.currentAppShortcut"

    init() {
        // Load saved shortcuts or use defaults
        if let data = UserDefaults.standard.data(forKey: Self.shortcutKey),
           let saved = try? JSONDecoder().decode(Shortcut.self, from: data) {
            self.shortcut = saved
        } else {
            self.shortcut = .defaultShortcut
        }

        if let data = UserDefaults.standard.data(forKey: Self.currentAppShortcutKey),
           let saved = try? JSONDecoder().decode(Shortcut.self, from: data) {
            self.currentAppShortcut = saved
        } else {
            self.currentAppShortcut = .defaultCurrentAppShortcut
        }
    }

    // MARK: - Public

    /// Start listening for the global shortcut.
    func start() {
        NSLog("[OptionTab] HotkeyManager.start() called")

        // Don't install twice
        if eventTap != nil {
            NSLog("[OptionTab] Event tap already installed, skipping")
            return
        }

        // Ensure Accessibility permission
        guard AccessibilityHelper.isAccessibilityGranted else {
            NSLog("[OptionTab] Accessibility NOT granted, cannot install event tap")
            return
        }

        NSLog("[OptionTab] Accessibility granted, installing event tap...")
        installEventTap()
    }

    /// Stop listening for the global shortcut.
    func stop() {
        removeEventTap()
    }

    /// Update the shortcut configuration.
    func updateShortcut(_ newShortcut: Shortcut) {
        shortcut = newShortcut
        if let encoded = try? JSONEncoder().encode(newShortcut) {
            UserDefaults.standard.set(encoded, forKey: Self.shortcutKey)
        }
        // Reinstall event tap with new shortcut
        removeEventTap()
        installEventTap()
    }

    /// Update the current app shortcut configuration.
    func updateCurrentAppShortcut(_ newShortcut: Shortcut) {
        currentAppShortcut = newShortcut
        if let encoded = try? JSONEncoder().encode(newShortcut) {
            UserDefaults.standard.set(encoded, forKey: Self.currentAppShortcutKey)
        }
        // Reinstall event tap with new shortcut
        removeEventTap()
        installEventTap()
    }

    /// Force the manager to deactivate (e.g. when a window is selected via mouse click).
    func forceDeactivate() {
        if isActive {
            isActive = false
            modifierPressed = false
            activeShortcut = nil
        }
    }

    // MARK: - Private

    private func installEventTap() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        // Context pointer for the callback
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyEventCallback,
            userInfo: context
        ) else {
            NSLog("[OptionTab] ❌ CGEvent.tapCreate FAILED — event tap could not be created")
            return
        }

        NSLog("[OptionTab] ✅ Event tap created successfully")
        self.eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[OptionTab] Event tap enabled and added to run loop")
    }

    private func removeEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
    }

    /// Re-enable the event tap if macOS disabled it.
    fileprivate func reEnableTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
}

// MARK: - CGEvent Tap Callback

/// Global CGEvent tap callback. Must be a free function (C calling convention).
/// Routes events to the HotkeyManager instance via the userInfo pointer.
private func hotkeyEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()

    // macOS can disable event taps if the callback is too slow or for other reasons.
    // Re-enable the tap when that happens.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        NSLog("[OptionTab] Event tap was disabled (type=%d), re-enabling...", type.rawValue)
        manager.reEnableTap()
        return Unmanaged.passUnretained(event)
    }

    switch type {
    case .keyDown:
        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        let matchesMain = keyCode == manager.shortcut.keyCode && manager.hasRequiredModifier(flags, for: manager.shortcut)
        let matchesCurrentApp = keyCode == manager.currentAppShortcut.keyCode && manager.hasRequiredModifier(flags, for: manager.currentAppShortcut)

        if matchesMain || matchesCurrentApp {
            let isShiftPressed = flags.contains(.maskShift)
            let forward = !isShiftPressed

            if !manager.isActive {
                manager.isActive = true
                manager.currentMode = matchesMain ? .allApps : .currentApp
                manager.activeShortcut = matchesMain ? manager.shortcut : manager.currentAppShortcut
                NSLog("[OptionTab] Shortcut detected — activating switcher in mode: \(manager.currentMode)")
                manager.onActivate?(manager.currentMode)
            } else {
                manager.onCycle?(forward)
            }
            return nil  // Consume the event
        }

        // If active and arrow/action keys are pressed, cycle or confirm
        if manager.isActive {
            let key = UInt16(keyCode)
            if key == UInt16(kVK_LeftArrow) {
                manager.onCycle?(false)
                return nil
            } else if key == UInt16(kVK_RightArrow) {
                manager.onCycle?(true)
                return nil
            } else if key == UInt16(kVK_Return) || key == UInt16(kVK_Space) {
                manager.isActive = false
                manager.modifierPressed = false
                manager.activeShortcut = nil
                manager.onDeactivate?(nil)
                return nil
            } else if key == UInt16(kVK_Escape) {
                manager.isActive = false
                manager.modifierPressed = false
                manager.activeShortcut = nil
                manager.onCancel?()
                return nil
            }
        }

    case .flagsChanged:
        let flags = event.flags

        // If the modifier is released while switcher is active, deactivate
        if manager.isActive, let activeShortcut = manager.activeShortcut, !manager.hasRequiredModifier(flags, for: activeShortcut) {
            manager.isActive = false
            manager.modifierPressed = false
            manager.activeShortcut = nil
            NSLog("[OptionTab] Modifier released — deactivating switcher")
            manager.onDeactivate?(nil)
        }

        if manager.isActive, let activeShortcut = manager.activeShortcut, manager.hasRequiredModifier(flags, for: activeShortcut) && !manager.modifierPressed {
            manager.modifierPressed = true
        }

        if manager.isActive, let activeShortcut = manager.activeShortcut, !manager.hasRequiredModifier(flags, for: activeShortcut) {
            manager.modifierPressed = false
        }

    default:
        break
    }

    return Unmanaged.passUnretained(event)
}

// MARK: - HotkeyManager Private Helpers

extension HotkeyManager {
    /// Convert the Shortcut's Carbon modifier flags to CGEventFlags for comparison
    /// against CGEvent.flags. Carbon flags (e.g. optionKey=2048) are completely
    /// different values from CGEventFlags (maskAlternate=524288).
    func hasRequiredModifier(_ flags: CGEventFlags, for shortcut: Shortcut) -> Bool {
        var required: CGEventFlags = []
        if shortcut.modifierFlags & UInt32(cmdKey)     != 0 { required.insert(.maskCommand) }
        if shortcut.modifierFlags & UInt32(optionKey)  != 0 { required.insert(.maskAlternate) }
        if shortcut.modifierFlags & UInt32(controlKey) != 0 { required.insert(.maskControl) }
        if shortcut.modifierFlags & UInt32(shiftKey)   != 0 { required.insert(.maskShift) }
        return flags.contains(required)
    }
}