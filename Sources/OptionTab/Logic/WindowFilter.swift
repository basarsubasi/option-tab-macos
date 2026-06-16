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
        ownPID: pid_t = WindowFilter.ownPID,
        validPIDs: Set<pid_t>? = nil
    ) -> [WindowItem] {
        windowList.compactMap { dict -> WindowItem? in
            guard let layer = dict[kCGWindowLayer as String] as? Int, layer == 0 else { return nil }
            guard let windowID = dict[kCGWindowNumber as String] as? CGWindowID else { return nil }
            guard let pid = dict[kCGWindowOwnerPID as String] as? pid_t else { return nil }

            // Exclude own app
            if pid == ownPID { return nil }

            // Only include windows from valid PIDs (e.g. regular apps), if provided
            if let validPIDs = validPIDs, !validPIDs.contains(pid) { return nil }

            // Exclude Dock and Window Server (redundant if using validPIDs, but safe)
            guard let ownerName = dict[kCGWindowOwnerName as String] as? String else { return nil }
            if ownerName == "Dock" || ownerName == "Window Server" { return nil }

            // Get window title. If empty (often due to missing Screen Recording permission),
            // try to fetch it via Accessibility API by matching the window's bounds.
            var title = dict[kCGWindowName as String] as? String ?? ""
            var bounds: CGRect = .zero
            if let boundsDict = dict[kCGWindowBounds as String] as? [String: CGFloat] {
                bounds = CGRect(
                    x: boundsDict["Height"] ?? 0 > 0 ? boundsDict["X"] ?? 0 : 0,
                    y: boundsDict["Height"] ?? 0 > 0 ? boundsDict["Y"] ?? 0 : 0,
                    width: boundsDict["Width"] ?? 0,
                    height: boundsDict["Height"] ?? 0
                )
            }
            
            if title.isEmpty && bounds.width > 0 {
                title = WindowFilter.fetchAXTitle(for: pid, windowID: windowID, matching: bounds)
            }

            // Exclude tiny windows (often transparent overlays or tooltips)
            if bounds.width <= 50 || bounds.height <= 50 { return nil }

            // Exclude windows with 0 alpha if present in dictionary
            if let alpha = dict[kCGWindowAlpha as String] as? CGFloat, alpha <= 0.0 { return nil }

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

    /// Fetches the window title using Accessibility API.
    /// Uses CGWindowID for perfect matching, with bounds as a fallback.
    /// This bypasses the need for Screen Recording permissions which restrict CGWindowList names.
    private static func fetchAXTitle(for pid: pid_t, windowID: CGWindowID, matching bounds: CGRect) -> String {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
        guard result == .success, let axWindows = windowsValue as? [AXUIElement] else { return "" }

        // 1. Try robust matching by CGWindowID
        for axWindow in axWindows {
            var axID: CGWindowID = 0
            if _AXUIElementGetWindow(axWindow, &axID) == .success, axID == windowID {
                var titleValue: CFTypeRef?
                if AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleValue) == .success {
                    return titleValue as? String ?? ""
                }
            }
        }

        // 2. Fallback to bounds matching
        for axWindow in axWindows {
            var positionValue: CFTypeRef?
            var sizeValue: CFTypeRef?
            
            if AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &positionValue) == .success,
               AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeValue) == .success {
                
                var point = CGPoint.zero
                var cgSize = CGSize.zero
                if let posVal = positionValue, let sizeVal = sizeValue,
                   AXValueGetValue(posVal as! AXValue, .cgPoint, &point),
                   AXValueGetValue(sizeVal as! AXValue, .cgSize, &cgSize) {
                    
                    let axBounds = CGRect(origin: point, size: cgSize)
                    // If bounds match within 1 pixel tolerance
                    if abs(axBounds.minX - bounds.minX) < 1 && abs(axBounds.minY - bounds.minY) < 1 &&
                       abs(axBounds.width - bounds.width) < 1 && abs(axBounds.height - bounds.height) < 1 {
                        
                        var titleValue: CFTypeRef?
                        if AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleValue) == .success {
                            return titleValue as? String ?? ""
                        }
                    }
                }
            }
        }
        return ""
    }
}