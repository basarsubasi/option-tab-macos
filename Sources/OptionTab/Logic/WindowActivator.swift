@preconcurrency import AppKit
@preconcurrency import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
@discardableResult
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: inout CGWindowID) -> AXError

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

        // Find the matching window robustly by its CGWindowID
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

            var axID: CGWindowID = 0
            if _AXUIElementGetWindow(axWindow, &axID) == .success, axID == window.id {
                AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                return
            }
        }

        // If no precise match, unminimize the first minimized window for this app
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

        // Try to find and raise the window by its CGWindowID
        for axWindow in axWindows {
            var axID: CGWindowID = 0
            if _AXUIElementGetWindow(axWindow, &axID) == .success, axID == window.id {
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(axWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                return
            }
        }
    }

    /// Closes a window using AXUIElement by simulating a click on the red close button.
    @MainActor
    static func close(_ window: WindowItem) {
        let appElement = AXUIElementCreateApplication(window.pid)
        var windowsValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        )

        guard result == .success, let axWindows = windowsValue as? [AXUIElement] else { return }

        // Find window by CGWindowID and close it
        for axWindow in axWindows {
            var axID: CGWindowID = 0
            if _AXUIElementGetWindow(axWindow, &axID) == .success, axID == window.id {
                clickCloseButton(of: axWindow)
                return
            }
        }
        
        // Fallback: if no match, close the first window
        if let first = axWindows.first {
            clickCloseButton(of: first)
        }
    }
    
    private static func clickCloseButton(of axWindow: AXUIElement) {
        var closeButtonValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWindow, kAXCloseButtonAttribute as CFString, &closeButtonValue) == .success {
            // Swift 6 / Foundation bridging quirk: sometimes it's wrapped, but as! AXUIElement works on CFTypeRef.
            let closeButton = closeButtonValue as! AXUIElement
            AXUIElementPerformAction(closeButton, kAXPressAction as CFString)
        }
    }
}