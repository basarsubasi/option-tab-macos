import Foundation
import CoreGraphics

/// Tracks windows in most-recently-used order.
/// The currently focused window is always position 0; the switcher starts selection at position 1.
/// Thread-safe via concurrent GCD queue with barrier writes.
final class MRUTracker: @unchecked Sendable {
    private var windows: [WindowItem] = []
    private let queue = DispatchQueue(label: "com.optiontab.mrutracker", attributes: .concurrent)

    /// Record that a window gained focus, updating its timestamp and re-sorting.
    func updateFocus(windowID: CGWindowID) {
        queue.async(flags: .barrier) { [windows] in
            var ws = windows
            if let index = ws.firstIndex(where: { $0.id == windowID }) {
                ws[index].lastFocusTime = ProcessInfo.processInfo.systemUptime
            }
            ws.sort { $0.lastFocusTime > $1.lastFocusTime }
            self.windows = ws
        }
    }

    /// Record focus for a window that may not yet be tracked (e.g., newly appeared).
    func updateFocus(window: WindowItem) {
        queue.async(flags: .barrier) { [windows] in
            var ws = windows
            var updated = window
            updated.lastFocusTime = ProcessInfo.processInfo.systemUptime
            if let index = ws.firstIndex(where: { $0.id == window.id }) {
                ws[index] = updated
            } else {
                ws.append(updated)
            }
            ws.sort { $0.lastFocusTime > $1.lastFocusTime }
            self.windows = ws
        }
    }

    /// Add a window to the tracker (e.g., from enumeration results).
    func addWindow(_ window: WindowItem) {
        queue.async(flags: .barrier) { [windows] in
            var ws = windows
            if ws.firstIndex(where: { $0.id == window.id }) == nil {
                ws.append(window)
            }
            self.windows = ws
        }
    }

    /// Remove a window from tracking (e.g., window closed, app quit).
    func removeWindow(windowID: CGWindowID) {
        queue.async(flags: .barrier) { [windows] in
            self.windows = windows.filter { $0.id != windowID }
        }
    }

    /// Remove all windows for a given app (e.g., app quit).
    func removeWindows(for pid: pid_t) {
        queue.async(flags: .barrier) { [windows] in
            self.windows = windows.filter { $0.pid != pid }
        }
    }

    /// Replace all tracked windows with a new set (e.g., from full enumeration).
    func replaceAll(_ newWindows: [WindowItem]) {
        queue.async(flags: .barrier) {
            self.windows = newWindows.sorted { $0.lastFocusTime > $1.lastFocusTime }
        }
    }

    /// Returns windows sorted by MRU order (most recent first).
    /// The switcher starts from index 1 (second-most-recent).
    func sortedWindows() -> [WindowItem] {
        queue.sync {
            windows.sorted { $0.lastFocusTime > $1.lastFocusTime }
        }
    }
}