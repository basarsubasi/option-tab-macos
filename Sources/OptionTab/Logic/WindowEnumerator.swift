@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics

/// Enumerates accessible windows on a concurrent background queue,
/// delivering results to the main queue.
final class WindowEnumerator: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.optiontab.enumerator", qos: .userInitiated)

    /// Enumerate all accessible windows and deliver the result on the main queue.
    func enumerate(completion: @escaping @Sendable ([WindowItem]) -> Void) {
        queue.async {
            let onScreen = self.enumerateOnScreen()
            let minimized = AccessibilityHelper.isAccessibilityGranted
                ? self.enumerateMinimized()
                : []
            let merged = WindowFilter.mergeMinimizedWindows(
                onScreen: onScreen,
                minimized: minimized
            )
            let filtered = WindowFilter.filterForCurrentSpace(windows: merged)
            DispatchQueue.main.async {
                completion(filtered)
            }
        }
    }

    /// Enumerate on-screen windows using CGWindowListCopyWindowInfo.
    private func enumerateOnScreen() -> [WindowItem] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return WindowFilter.filterOnScreenWindows(from: windowList)
    }

    /// Enumerate minimized windows by querying each running app's AXUIElement.
    private func enumerateMinimized() -> [WindowItem] {
        var minimizedWindows: [WindowItem] = []
        let runningApps = NSWorkspace.shared.runningApplications

        for app in runningApps {
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { continue }
            guard app.processIdentifier != 0 else { continue }

            let pid = app.processIdentifier
            let appElement = AXUIElementCreateApplication(pid)
            var windowsValue: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(
                appElement,
                kAXWindowsAttribute as CFString,
                &windowsValue
            )

            guard result == .success, let axWindows = windowsValue as? [AXUIElement] else {
                continue
            }

            for axWindow in axWindows {
                var isMinimizedValue: CFTypeRef?
                let minimizedResult = AXUIElementCopyAttributeValue(
                    axWindow,
                    kAXMinimizedAttribute as CFString,
                    &isMinimizedValue
                )

                guard minimizedResult == .success,
                      let isMinimized = isMinimizedValue as? Bool,
                      isMinimized else {
                    continue
                }

                // Get window title
                var titleValue: CFTypeRef?
                let titleResult = AXUIElementCopyAttributeValue(
                    axWindow,
                    kAXTitleAttribute as CFString,
                    &titleValue
                )
                let title = (titleResult == .success) ? (titleValue as? String ?? "") : ""

                // Get window position and size
                var positionValue: CFTypeRef?
                let posResult = AXUIElementCopyAttributeValue(
                    axWindow,
                    kAXPositionAttribute as CFString,
                    &positionValue
                )
                var sizeValue: CFTypeRef?
                let sizeResult = AXUIElementCopyAttributeValue(
                    axWindow,
                    kAXSizeAttribute as CFString,
                    &sizeValue
                )

                var bounds: CGRect = .zero
                if posResult == .success, sizeResult == .success {
                    var point = CGPoint.zero
                    var cgSize = CGSize.zero
                    if let posVal = positionValue, let sizeVal = sizeValue,
                       AXValueGetValue(posVal as! AXValue, .cgPoint, &point),
                       AXValueGetValue(sizeVal as! AXValue, .cgSize, &cgSize) {
                        bounds = CGRect(origin: point, size: cgSize)
                    }
                }

                // For minimized windows, create a synthetic ID from PID + hash
                // (they're not in CGWindowList, so we need a stable identifier)
                let windowID = CGWindowID(truncatingIfNeeded: hashAXElement(axWindow))

                let appIcon = NSRunningApplication(processIdentifier: pid)?.icon

                let windowItem = WindowItem(
                    id: windowID,
                    pid: pid,
                    appName: app.localizedName ?? "",
                    title: title,
                    bounds: bounds,
                    isMinimized: true,
                    appIcon: appIcon,
                    lastFocusTime: 0
                )
                minimizedWindows.append(windowItem)
            }
        }

        return minimizedWindows
    }

    /// Produce a stable hash for an AXUIElement to use as a synthetic CGWindowID.
    private func hashAXElement(_ element: AXUIElement) -> CFHashCode {
        CFHash(element as CFTypeRef)
    }
}