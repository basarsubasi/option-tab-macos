import AppKit
import Carbon
import ServiceManagement

/// Manages the menu bar status item and its menu.
@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem!
    private var hotkeyManager: HotkeyManager?

    func setup(hotkeyManager: HotkeyManager) {
        self.hotkeyManager = hotkeyManager

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "switch.2", accessibilityDescription: "OptionTab")
            button.image?.size = NSSize(width: 18, height: 18)
        }

        let menu = NSMenu()

        // Shortcut display
        let shortcutItem = NSMenuItem(
            title: "Shortcut: \(hotkeyManager.shortcut.displayString)",
            action: nil,
            keyEquivalent: ""
        )
        shortcutItem.isEnabled = false
        menu.addItem(shortcutItem)

        menu.addItem(NSMenuItem.separator())

        // Change Shortcut
        let changeShortcutItem = NSMenuItem(
            title: "Change Shortcut\u{2026}",
            action: #selector(changeShortcut),
            keyEquivalent: ""
        )
        menu.addItem(changeShortcutItem)

        menu.addItem(NSMenuItem.separator())

        // Start at Login
        let startAtLoginItem = NSMenuItem(
            title: "Start at Login",
            action: #selector(toggleStartAtLogin),
            keyEquivalent: ""
        )
        startAtLoginItem.state = isStartAtLoginEnabled() ? .on : .off
        menu.addItem(startAtLoginItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit OptionTab",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func changeShortcut() {
        let alert = NSAlert()
        alert.messageText = "Change Shortcut"
        alert.informativeText = "Press the new key combination to set as the switcher shortcut.\nCurrent shortcut: \(hotkeyManager?.shortcut.displayString ?? "Opt+Tab")"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Cancel")

        // Create a custom view that captures key presses
        let shortcutRecorder = ShortcutRecorderView()
        shortcutRecorder.onShortcutSet = { [weak self] shortcut in
            self?.hotkeyManager?.updateShortcut(shortcut)
            // Update menu item title
            if let menuItem = self?.statusItem.menu?.items.first {
                menuItem.title = "Shortcut: \(shortcut.displayString)"
            }
            alert.window.close()
        }
        alert.accessoryView = shortcutRecorder

        alert.runModal()
    }

    @objc private func toggleStartAtLogin(_ sender: NSMenuItem) {
        if isStartAtLoginEnabled() {
            disableStartAtLogin()
            sender.state = .off
        } else {
            enableStartAtLogin()
            sender.state = .on
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Login Item Management

    private func isStartAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            return false
        }
    }

    private func enableStartAtLogin() {
        if #available(macOS 13.0, *) {
            try? SMAppService.mainApp.register()
        }
    }

    private func disableStartAtLogin() {
        if #available(macOS 13.0, *) {
            try? SMAppService.mainApp.unregister()
        }
    }
}

/// A custom view that captures key combinations for shortcut configuration.
@MainActor
final class ShortcutRecorderView: NSView {
    var onShortcutSet: ((HotkeyManager.Shortcut) -> Void)?
    private var isRecording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 40))
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 4
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor

        let label = NSTextField(labelWithString: "Click here, then press a key combination\u{2026}")
        label.textColor = .placeholderTextColor
        label.font = .systemFont(ofSize: 13)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = 2
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        let keyCode = UInt32(event.keyCode)
        var modifierFlags: UInt32 = 0
        if event.modifierFlags.contains(.command) { modifierFlags |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.option) { modifierFlags |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { modifierFlags |= UInt32(controlKey) }
        if event.modifierFlags.contains(.shift) { modifierFlags |= UInt32(shiftKey) }

        // Require at least one modifier
        guard modifierFlags != 0 else {
            NSSound.beep()
            return
        }

        let shortcut = HotkeyManager.Shortcut(keyCode: keyCode, modifierFlags: modifierFlags)
        isRecording = false
        onShortcutSet?(shortcut)
    }
}