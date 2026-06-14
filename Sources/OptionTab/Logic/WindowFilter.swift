@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics

/// Filters raw window lists into accessible windows for the current Space.
struct WindowFilter {
    /// Whether Accessibility permission is currently granted.
    static var isAccessibilityGranted: Bool {
        AccessibilityHelper.isAccessibilityGranted
    }

    /// The process ID of the current app (to exclude our own windows).
    /// Set once at launch; never changes. Safe to read from any isolation domain.
    static let ownPID: pid_t = ProcessInfo.processInfo.processIdentifier

    /// Filter on-screen windows from CGWindowListCopyWindowInfo.
    /// Returns windows with layer 0, excluding own app, Dock, and Desktop.
    static func filterOnScreenWindows(
        from windowList: [[String: Any]],
        ownPID: pid_t = WindowFilter.ownPID
    ) -> [WindowItem] {
        windowList.compactMap { dict -> WindowItem? in
            guard let layer = dict[kCGWindowLayer as String] as? Int, layer == 0 else { return nil }
            guard let windowID = dict[kCGWindowNumber as String] as? CGWindowID else { return nil }
            guard let pid = dict[kCGWindowOwnerPID as String] as? pid_t else { return nil }

            // Exclude own app
            if pid == ownPID { return nil }

            // Exclude Dock and Window Server
            guard let ownerName = dict[kCGWindowOwnerName as String] as? String else { return nil }
            if ownerName == "Dock" || ownerName == "Window Server" { return nil }

            let title = dict[kCGWindowName as String] as? String ?? ""

            var bounds: CGRect = .zero
            if let boundsDict = dict[kCGWindowBounds as String] as? [String: CGFloat] {
                bounds = CGRect(
                    x: boundsDict["Height"] ?? 0 > 0 ? boundsDict["X"] ?? 0 : 0,
                    y: boundsDict["Height"] ?? 0 > 0 ? boundsDict["Y"] ?? 0 : 0,
                    width: boundsDict["Width"] ?? 0,
                    height: boundsDict["Height"] ?? 0
                )
            }

            let appIcon = NSRunningApplication(processIdentifier: pid)?.icon

            return WindowItem(
                id: windowID,
                pid: pid,
                appName: ownerName,
                title: title,
                bounds: bounds,
                isMinimized: false,
                appIcon: appIcon,
                lastFocusTime: 0
            )
        }
    }

    /// Merge minimized windows from AXUIElement queries into the existing list.
    /// Deduplicates by CGWindowID.
    static func mergeMinimizedWindows(
        onScreen: [WindowItem],
        minimized: [WindowItem]
    ) -> [WindowItem] {
        var seen = Set<CGWindowID>()
        var result: [WindowItem] = []

        for window in onScreen {
            seen.insert(window.id)
            result.append(window)
        }

        for window in minimized where !seen.contains(window.id) {
            seen.insert(window.id)
            result.append(window)
        }

        return result
    }

    /// Filter windows to only those on the current Space.
    /// When Accessibility is not granted, we can only show on-screen windows.
    static func filterForCurrentSpace(
        windows: [WindowItem],
        accessibilityGranted: Bool = WindowFilter.isAccessibilityGranted
    ) -> [WindowItem] {
        if accessibilityGranted {
            // With Accessibility, we include minimized windows too
            // (they're associated with the current Space by macOS)
            return windows
        } else {
            // Without Accessibility, only on-screen windows are visible
            return windows.filter { !$0.isMinimized }
        }
    }
}