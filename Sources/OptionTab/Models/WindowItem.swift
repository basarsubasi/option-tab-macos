import AppKit
import CoreGraphics

/// Represents a single OS window that can appear in the switcher.
/// Marked Sendable for safe cross-actor transfer (e.g., background enumeration → main actor).
struct WindowItem: Identifiable, Equatable, Sendable {
    let id: CGWindowID
    let pid: pid_t
    let appName: String
    let title: String
    let bounds: CGRect
    let isMinimized: Bool
    let appIcon: NSImage?
    var lastFocusTime: TimeInterval

    static func == (lhs: WindowItem, rhs: WindowItem) -> Bool {
        lhs.id == rhs.id
    }
}