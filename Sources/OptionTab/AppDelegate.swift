import AppKit
@preconcurrency import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var hotkeyManager: HotkeyManager?
    private var mruTracker: MRUTracker?
    private var switcherPanel: SwitcherPanel?
    private let windowEnumerator = WindowEnumerator()
    private var accessibilityTimer: Timer?
    private var focusTrackerRef: FocusTracker?

    // State to handle fast hotkey presses during enumeration
    private var isEnumerating = false
    private var pendingCycleSteps = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[OptionTab] App launched")

        // Apply saved theme
        let currentTheme = UserDefaults.standard.string(forKey: "AppTheme") ?? "System"
        if currentTheme == "Light" {
            NSApp.appearance = NSAppearance(named: .aqua)
        } else if currentTheme == "Dark" {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        
        // Force Dock to use our icon (bypasses macOS icon caching bugs)
        if let iconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns") {
            NSApp.applicationIconImage = NSImage(contentsOfFile: iconPath)
        }

        // Initialize core components
        let tracker = MRUTracker()
        mruTracker = tracker

        let panel = SwitcherPanel()
        switcherPanel = panel
        
        panel.onCloseWindow = { [weak self] window in
            Task { @MainActor in
                guard let self = self else { return }
                // 1. Physically close the window via Accessibility
                WindowActivator.close(window)
                // 2. Remove it from the MRU queue so it doesn't reappear
                self.mruTracker?.removeWindow(windowID: window.id)
                // 3. Remove it from the UI immediately
                self.switcherPanel?.removeWindow(withId: window.id)
            }
        }
        
        panel.onSelectWindow = { [weak self] window in
            Task { @MainActor in
                self?.hotkeyManager?.forceDeactivate()
                self?.activateWindow(window)
            }
        }

        let hotkey = HotkeyManager()
        hotkeyManager = hotkey

        let menuBar = MenuBarController()
        menuBarController = menuBar

        // Wire up hotkey → switcher panel
        hotkey.onActivate = { [weak self] in
            Task { @MainActor in
                self?.isEnumerating = true
                self?.pendingCycleSteps = 0
                self?.showSwitcher()
            }
        }
        hotkey.onCycle = { [weak self] forward in
            Task { @MainActor in
                guard let self = self else { return }
                if self.isEnumerating {
                    self.pendingCycleSteps += (forward ? 1 : -1)
                } else {
                    if forward {
                        self.switcherPanel?.cycleNext()
                    } else {
                        self.switcherPanel?.cyclePrevious()
                    }
                }
            }
        }
        hotkey.onDeactivate = { [weak self] _ in
            Task { @MainActor in
                let selected = self?.switcherPanel?.selectedWindow
                self?.activateWindow(selected)
            }
        }
        hotkey.onCancel = { [weak self] in
            Task { @MainActor in
                self?.switcherPanel?.hide()
            }
        }

        // Start focus tracking — hold a reference so it stays alive
        let focusTracker = FocusTracker(tracker: tracker)
        focusTracker.start()
        focusTrackerRef = focusTracker

        // Start menu bar
        menuBar.setup(hotkeyManager: hotkey)

        // Prompt for Accessibility permission, then start hotkey when granted
        startAccessibilityPolling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        accessibilityTimer?.invalidate()
        hotkeyManager?.stop()
    }

    /// Prompt for Accessibility and keep checking every second until granted.
    /// CGEvent tap creation requires Accessibility to already be granted.
    private func startAccessibilityPolling() {
        let alreadyTrusted = AccessibilityHelper.checkPermission(prompt: true)
        NSLog("[OptionTab] Accessibility trusted: %@", alreadyTrusted ? "YES" : "NO")

        if alreadyTrusted {
            hotkeyManager?.start()
            NSLog("[OptionTab] Hotkey manager started immediately")
            return
        }

        // Poll until the user grants permission
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                if AccessibilityHelper.isAccessibilityGranted {
                    self?.accessibilityTimer?.invalidate()
                    self?.accessibilityTimer = nil
                    self?.hotkeyManager?.start()
                    NSLog("[OptionTab] Accessibility granted — hotkey manager started")
                }
            }
        }
    }

    private func showSwitcher() {
        // Enumerate live windows first, then sort by MRU order
        windowEnumerator.enumerate { [weak self] liveWindows in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isEnumerating = false

                let mruOrder = self.mruTracker?.sortedWindows() ?? []

                // Sort live windows by MRU: windows seen in tracker come first (by their tracked order),
                // new windows (not yet tracked) are appended at the end.
                let mruIDs = mruOrder.map(\.id)
                let sorted = liveWindows.sorted { a, b in
                    let ai = mruIDs.firstIndex(of: a.id) ?? Int.max
                    let bi = mruIDs.firstIndex(of: b.id) ?? Int.max
                    // Important: if both are Int.max (unknown to MRU tracker), keep their original Z-order (front-to-back)
                    if ai == Int.max && bi == Int.max { return false }
                    return ai < bi
                }

                self.switcherPanel?.show(with: sorted)

                // Apply any tab presses that happened while we were enumerating
                if self.pendingCycleSteps > 0 {
                    for _ in 0..<self.pendingCycleSteps { self.switcherPanel?.cycleNext() }
                } else if self.pendingCycleSteps < 0 {
                    for _ in 0..<abs(self.pendingCycleSteps) { self.switcherPanel?.cyclePrevious() }
                }
                self.pendingCycleSteps = 0
            }
        }
    }

    private func activateWindow(_ window: WindowItem?) {
        switcherPanel?.hide()
        guard let window = window else { return }
        WindowActivator.activate(window)
    }

    // MARK: - Dock Menu & Theme Management

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu()
        
        let systemItem = NSMenuItem(title: "System", action: #selector(setThemeSystem), keyEquivalent: "")
        let lightItem = NSMenuItem(title: "Light", action: #selector(setThemeLight), keyEquivalent: "")
        let darkItem = NSMenuItem(title: "Dark", action: #selector(setThemeDark), keyEquivalent: "")
        
        let currentTheme = UserDefaults.standard.string(forKey: "AppTheme") ?? "System"
        systemItem.state = currentTheme == "System" ? .on : .off
        lightItem.state = currentTheme == "Light" ? .on : .off
        darkItem.state = currentTheme == "Dark" ? .on : .off
        
        themeMenu.addItem(systemItem)
        themeMenu.addItem(lightItem)
        themeMenu.addItem(darkItem)
        
        themeItem.submenu = themeMenu
        menu.addItem(themeItem)
        
        return menu
    }

    @objc private func setThemeSystem() {
        UserDefaults.standard.set("System", forKey: "AppTheme")
        NSApp.appearance = nil
    }

    @objc private func setThemeLight() {
        UserDefaults.standard.set("Light", forKey: "AppTheme")
        NSApp.appearance = NSAppearance(named: .aqua)
    }

    @objc private func setThemeDark() {
        UserDefaults.standard.set("Dark", forKey: "AppTheme")
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }
}

/// Wraps Accessibility permission checks, isolating Swift 6 Sendability concerns
/// for C global constants like kAXTrustedCheckOptionPrompt.
enum AccessibilityHelper {
    /// Check whether Accessibility permission is granted, optionally prompting.
    static func checkPermission(prompt: Bool = true) -> Bool {
        // kAXTrustedCheckOptionPrompt is an immutable process-global constant.
        // nonisolated(unsafe) tells Swift 6 that this read is safe across isolation boundaries.
        nonisolated(unsafe) let promptKey = kAXTrustedCheckOptionPrompt
        let options = [promptKey.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Check Accessibility permission without prompting.
    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }
}