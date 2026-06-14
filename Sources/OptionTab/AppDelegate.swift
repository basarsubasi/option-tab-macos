import AppKit
@preconcurrency import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var hotkeyManager: HotkeyManager?
    private var mruTracker: MRUTracker?
    private var switcherPanel: SwitcherPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check Accessibility permission
        ensureAccessibility()

        // Initialize core components
        let tracker = MRUTracker()
        mruTracker = tracker

        let panel = SwitcherPanel()
        switcherPanel = panel

        let hotkey = HotkeyManager()
        hotkeyManager = hotkey

        let menuBar = MenuBarController()
        menuBarController = menuBar

        // Wire up hotkey → switcher panel
        hotkey.onActivate = { [weak self] in
            Task { @MainActor in
                self?.showSwitcher()
            }
        }
        hotkey.onCycleNext = { [weak self] in
            Task { @MainActor in
                self?.switcherPanel?.cycleNext()
            }
        }
        hotkey.onDeactivate = { [weak self] selectedWindow in
            Task { @MainActor in
                self?.activateWindow(selectedWindow)
            }
        }

        // Start focus tracking
        let focusTracker = FocusTracker(tracker: tracker)
        focusTracker.start()

        // Start menu bar
        menuBar.setup(hotkeyManager: hotkey)

        // Start hotkey
        hotkey.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.stop()
    }

    private func ensureAccessibility() {
        let trusted = AccessibilityHelper.checkPermission()
        if !trusted {
            // System will prompt for Accessibility permission
            // App continues in degraded mode (on-screen windows only)
        }
    }

    private func showSwitcher() {
        guard let tracker = mruTracker else { return }
        let windows = tracker.sortedWindows()
        switcherPanel?.show(with: windows)
    }

    private func activateWindow(_ window: WindowItem?) {
        switcherPanel?.hide()
        guard let window = window else { return }
        WindowActivator.activate(window)
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