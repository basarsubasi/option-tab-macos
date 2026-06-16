import AppKit
import Carbon
import ServiceManagement

/// Manages the menu bar status item and its menu.
@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var hotkeyManager: HotkeyManager?

    func setup(hotkeyManager: HotkeyManager) {
        self.hotkeyManager = hotkeyManager

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            let appIcon = NSImage(named: NSImage.applicationIconName)
            appIcon?.size = NSSize(width: 18, height: 18)
            button.image = appIcon
        }

        let menu = NSMenu()
        menu.autoenablesItems = false

        // Main Shortcut display
        let shortcutItem = NSMenuItem(
            title: "Main Shortcut: \(hotkeyManager.shortcut.displayString)",
            action: nil,
            keyEquivalent: ""
        )
        shortcutItem.isEnabled = false
        menu.addItem(shortcutItem)

        // Current App Shortcut display
        let currentAppShortcutItem = NSMenuItem(
            title: "Current App Shortcut: \(hotkeyManager.currentAppShortcut.displayString)",
            action: nil,
            keyEquivalent: ""
        )
        currentAppShortcutItem.isEnabled = false
        menu.addItem(currentAppShortcutItem)

        menu.addItem(NSMenuItem.separator())

        // Change Main Shortcut
        let changeShortcutItem = NSMenuItem(
            title: "Change Main Shortcut\u{2026}",
            action: #selector(changeShortcut),
            keyEquivalent: ""
        )
        changeShortcutItem.target = self
        changeShortcutItem.isEnabled = true
        menu.addItem(changeShortcutItem)

        // Change Current App Shortcut
        let changeCurrentAppShortcutItem = NSMenuItem(
            title: "Change Current App Shortcut\u{2026}",
            action: #selector(changeCurrentAppShortcut),
            keyEquivalent: ""
        )
        changeCurrentAppShortcutItem.target = self
        changeCurrentAppShortcutItem.isEnabled = true
        menu.addItem(changeCurrentAppShortcutItem)

        menu.addItem(NSMenuItem.separator())
        
        // Theme
        let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu()
        
        let systemItem = NSMenuItem(title: "System", action: #selector(setThemeSystem), keyEquivalent: "")
        let lightItem = NSMenuItem(title: "Light", action: #selector(setThemeLight), keyEquivalent: "")
        let darkItem = NSMenuItem(title: "Dark", action: #selector(setThemeDark), keyEquivalent: "")
        
        systemItem.target = self
        lightItem.target = self
        darkItem.target = self
        
        let currentTheme = UserDefaults.standard.string(forKey: "AppTheme") ?? "System"
        systemItem.state = currentTheme == "System" ? .on : .off
        lightItem.state = currentTheme == "Light" ? .on : .off
        darkItem.state = currentTheme == "Dark" ? .on : .off
        
        themeMenu.addItem(systemItem)
        themeMenu.addItem(lightItem)
        themeMenu.addItem(darkItem)
        
        themeItem.submenu = themeMenu
        menu.addItem(themeItem)

        menu.addItem(NSMenuItem.separator())

        // Start at Login
        let startAtLoginItem = NSMenuItem(
            title: "Start at Login",
            action: #selector(toggleStartAtLogin),
            keyEquivalent: ""
        )
        startAtLoginItem.target = self
        startAtLoginItem.isEnabled = true
        startAtLoginItem.state = isStartAtLoginEnabled() ? .on : .off
        menu.addItem(startAtLoginItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit OptionTab",
            action: #selector(quit),
            keyEquivalent: ""
        )
        quitItem.target = self
        quitItem.isEnabled = true
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func changeShortcut() {
        let alert = NSAlert()
        alert.messageText = "Change Main Shortcut"
        alert.informativeText = "Press the new key combination to set as the main switcher shortcut.\nCurrent shortcut: \(hotkeyManager?.shortcut.displayString ?? "Opt+Tab")"
        alert.alertStyle = .informational
        
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")

        // Create a custom view that captures key presses
        let shortcutRecorder = ShortcutRecorderView()
        alert.accessoryView = shortcutRecorder

        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn, let newShortcut = shortcutRecorder.recordedShortcut {
            self.hotkeyManager?.updateShortcut(newShortcut)
            // Update menu item title
            if let menuItem = self.statusItem.menu?.items.first(where: { $0.title.starts(with: "Main Shortcut:") }) {
                menuItem.title = "Main Shortcut: \(newShortcut.displayString)"
            }
        }
    }

    @objc private func changeCurrentAppShortcut() {
        let alert = NSAlert()
        alert.messageText = "Change Current App Shortcut"
        alert.informativeText = "Press the new key combination to set as the current app switcher shortcut.\nCurrent shortcut: \(hotkeyManager?.currentAppShortcut.displayString ?? "Opt+Q")"
        alert.alertStyle = .informational
        
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")

        // Create a custom view that captures key presses
        let shortcutRecorder = ShortcutRecorderView()
        alert.accessoryView = shortcutRecorder

        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn, let newShortcut = shortcutRecorder.recordedShortcut {
            self.hotkeyManager?.updateCurrentAppShortcut(newShortcut)
            // Update menu item title
            if let menuItem = self.statusItem.menu?.items.first(where: { $0.title.starts(with: "Current App Shortcut:") }) {
                menuItem.title = "Current App Shortcut: \(newShortcut.displayString)"
            }
        }
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

    @objc private func setThemeSystem() {
        UserDefaults.standard.set("System", forKey: "AppTheme")
        NSApp.appearance = nil
        updateThemeMenu()
    }

    @objc private func setThemeLight() {
        UserDefaults.standard.set("Light", forKey: "AppTheme")
        NSApp.appearance = NSAppearance(named: .aqua)
        updateThemeMenu()
    }

    @objc private func setThemeDark() {
        UserDefaults.standard.set("Dark", forKey: "AppTheme")
        NSApp.appearance = NSAppearance(named: .darkAqua)
        updateThemeMenu()
    }
    
    private func updateThemeMenu() {
        guard let themeMenu = statusItem.menu?.item(withTitle: "Theme")?.submenu else { return }
        let currentTheme = UserDefaults.standard.string(forKey: "AppTheme") ?? "System"
        themeMenu.item(withTitle: "System")?.state = currentTheme == "System" ? .on : .off
        themeMenu.item(withTitle: "Light")?.state = currentTheme == "Light" ? .on : .off
        themeMenu.item(withTitle: "Dark")?.state = currentTheme == "Dark" ? .on : .off
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
    var recordedShortcut: HotkeyManager.Shortcut?
    private var isRecording = false
    private var label: NSTextField!

    override var acceptsFirstResponder: Bool { true }

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

        label = NSTextField(labelWithString: "Click here, then press a key combination\u{2026}")
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        isRecording = true
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = 2
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = 2
        super.mouseDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isRecording {
            keyDown(with: event)
            return true
        }
        return super.performKeyEquivalent(with: event)
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

        let shortcut = HotkeyManager.Shortcut(keyCode: keyCode, modifierFlags: modifierFlags)
        recordedShortcut = shortcut
        
        label.stringValue = shortcut.displayString
        label.textColor = .labelColor
    }
}