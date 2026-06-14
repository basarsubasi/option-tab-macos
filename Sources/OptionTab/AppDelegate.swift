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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[OptionTab] App launched")

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
        hotkey.onDeactivate = { [weak self] _ in
            Task { @MainActor in
                let selected = self?.switcherPanel?.selectedWindow
                self?.activateWindow(selected)
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
                let mruOrder = self.mruTracker?.sortedWindows() ?? []

                // Sort live windows by MRU: windows seen in tracker come first (by their tracked order),
                // new windows (not yet tracked) are appended at the end.
                let mruIDs = mruOrder.map(\.id)
                let sorted = liveWindows.sorted { a, b in
                    let ai = mruIDs.firstIndex(of: a.id) ?? Int.max
                    let bi = mruIDs.firstIndex(of: b.id) ?? Int.max
                    return ai < bi
                }

                self.switcherPanel?.show(with: sorted)
            }
        }
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