@preconcurrency import AppKit
@preconcurrency import ApplicationServices

/// Activates a window: unminimizes if needed, raises, and focuses the owning app.
enum WindowActivator {
    /// Activate the given window.
    @MainActor
    static func activate(_ window: WindowItem) {
        let pid = window.pid

        // If minimized, unminimize via AXUIElement
        if window.isMinimized, AccessibilityHelper.isAccessibilityGranted {
            unminimize(window: window)
        }

        // Raise the window via AXUIElement (if Accessibility is granted)
        if AccessibilityHelper.isAccessibilityGranted {
            raiseAXWindow(window: window)
        }

        // Activate the owning app
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    /// Unminimize a window using AXUIElement.
    @MainActor
    private static func unminimize(window: WindowItem) {
        let appElement = AXUIElementCreateApplication(window.pid)
        var windowsValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        )

        guard result == .success else {
            // Fallback: activate the app, which may restore the window
            if let app = NSRunningApplication(processIdentifier: window.pid) {
                app.activate(options: [.activateIgnoringOtherApps])
            }
            return
        }

        guard let axWindows = windowsValue as? [AXUIElement] else { return }

        // Find the matching window by title
        for axWindow in axWindows {
            var isMinimizedValue: CFTypeRef?
            let minimizedResult = AXUIElementCopyAttributeValue(
                axWindow,
                kAXMinimizedAttribute as CFString,
                &isMinimizedValue
            )

            guard minimizedResult == .success,
                  let isMinimized = isMinimizedValue as? Bool,
                  isMinimized else { continue }

            // Match by title if available
            if !window.title.isEmpty {
                var titleValue: CFTypeRef?
                AXUIElementCopyAttributeValue(
                    axWindow,
                    kAXTitleAttribute as CFString,
                    &titleValue
                )
                if let title = titleValue as? String, title == window.title {
                    AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                    AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                    return
                }
            }
        }

        // If no title match, unminimize the first minimized window for this app
        for axWindow in axWindows {
            var isMinimizedValue: CFTypeRef?
            let minimizedResult = AXUIElementCopyAttributeValue(
                axWindow,
                kAXMinimizedAttribute as CFString,
                &isMinimizedValue
            )

            if minimizedResult == .success,
               let isMinimized = isMinimizedValue as? Bool,
               isMinimized {
                AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                return
            }
        }
    }

    /// Raise an AXUIElement window.
    @MainActor
    private static func raiseAXWindow(window: WindowItem) {
        let appElement = AXUIElementCreateApplication(window.pid)
        var windowsValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        )

        guard result == .success, let axWindows = windowsValue as? [AXUIElement] else { return }

        // Try to find and raise the window by title
        for axWindow in axWindows {
            var titleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleValue)

            if let title = titleValue as? String, title == window.title {
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(axWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                return
            }
        }
    }
}