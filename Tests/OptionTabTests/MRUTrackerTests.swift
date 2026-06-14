import Testing
import Foundation
import CoreGraphics
@testable import OptionTab

final class MRUTrackerTests {

    private func makeWindow(id: CGWindowID, pid: pid_t = 1000, lastFocusTime: TimeInterval = 0) -> WindowItem {
        WindowItem(
            id: id,
            pid: pid,
            appName: "TestApp",
            title: "Window \(id)",
            bounds: .zero,
            isMinimized: false,
            appIcon: nil,
            lastFocusTime: lastFocusTime
        )
    }

    @Test("MRUTracker sortedWindows returns windows sorted by lastFocusTime descending")
    func testSortedByFocusTime() async {
        let tracker = MRUTracker()
        let w1 = makeWindow(id: 1, lastFocusTime: 100)
        let w2 = makeWindow(id: 2, lastFocusTime: 300)
        let w3 = makeWindow(id: 3, lastFocusTime: 200)

        tracker.replaceAll([w1, w2, w3])

        // Small delay for async barrier write
        try? await Task.sleep(for: .milliseconds(100))

        let sorted = tracker.sortedWindows()
        #expect(sorted[0].id == 2)  // most recent
        #expect(sorted[1].id == 3)
        #expect(sorted[2].id == 1)  // least recent
    }

    @Test("MRUTracker updateFocus(windowID:) promotes window to top")
    func testUpdateFocusByID() async {
        let tracker = MRUTracker()
        let w1 = makeWindow(id: 1, lastFocusTime: 100)
        let w2 = makeWindow(id: 2, lastFocusTime: 200)
        let w3 = makeWindow(id: 3, lastFocusTime: 300)

        tracker.replaceAll([w1, w2, w3])

        // Focus w1 — it should become most recent
        tracker.updateFocus(windowID: 1)

        try? await Task.sleep(for: .milliseconds(100))

        let sorted = tracker.sortedWindows()
        #expect(sorted[0].id == 1)
    }

    @Test("MRUTracker updateFocus(window:) adds new window to top")
    func testUpdateFocusNewWindow() async {
        let tracker = MRUTracker()
        let w1 = makeWindow(id: 1, lastFocusTime: 100)

        tracker.replaceAll([w1])

        let w2 = makeWindow(id: 2, lastFocusTime: 0)
        tracker.updateFocus(window: w2)

        try? await Task.sleep(for: .milliseconds(100))

        let sorted = tracker.sortedWindows()
        #expect(sorted.count == 2)
        #expect(sorted[0].id == 2)  // newly focused window on top
    }

    @Test("MRUTracker removeWindow removes specific window")
    func testRemoveWindow() async {
        let tracker = MRUTracker()
        let w1 = makeWindow(id: 1, lastFocusTime: 100)
        let w2 = makeWindow(id: 2, lastFocusTime: 200)

        tracker.replaceAll([w1, w2])
        tracker.removeWindow(windowID: 1)

        try? await Task.sleep(for: .milliseconds(100))

        let sorted = tracker.sortedWindows()
        #expect(sorted.count == 1)
        #expect(sorted[0].id == 2)
    }

    @Test("MRUTracker removeWindows(for:) removes all windows of a given app")
    func testRemoveWindowsForPID() async {
        let tracker = MRUTracker()
        let w1 = makeWindow(id: 1, pid: 1000, lastFocusTime: 100)
        let w2 = makeWindow(id: 2, pid: 1000, lastFocusTime: 200)
        let w3 = makeWindow(id: 3, pid: 2000, lastFocusTime: 300)

        tracker.replaceAll([w1, w2, w3])
        tracker.removeWindows(for: 1000)

        try? await Task.sleep(for: .milliseconds(100))

        let sorted = tracker.sortedWindows()
        #expect(sorted.count == 1)
        #expect(sorted[0].id == 3)
    }

    @Test("MRUTracker addWindow does not duplicate existing window")
    func testAddWindowNoDuplicate() async {
        let tracker = MRUTracker()
        let w1 = makeWindow(id: 1, lastFocusTime: 100)

        tracker.replaceAll([w1])
        tracker.addWindow(w1)  // should not duplicate

        try? await Task.sleep(for: .milliseconds(100))

        let sorted = tracker.sortedWindows()
        #expect(sorted.count == 1)
    }

    @Test("MRUTracker second-most-recent window is at index 1")
    func testSecondMostRecent() async {
        let tracker = MRUTracker()
        let w1 = makeWindow(id: 1, lastFocusTime: 100)
        let w2 = makeWindow(id: 2, lastFocusTime: 200)
        let w3 = makeWindow(id: 3, lastFocusTime: 300)

        tracker.replaceAll([w1, w2, w3])

        try? await Task.sleep(for: .milliseconds(100))

        let sorted = tracker.sortedWindows()
        // Index 0 = most recent (currently focused), index 1 = switcher start
        #expect(sorted[0].id == 3)
        #expect(sorted[1].id == 2)
    }

    @Test("MRUTracker empty list returns empty")
    func testEmptyList() {
        let tracker = MRUTracker()
        let sorted = tracker.sortedWindows()
        #expect(sorted.isEmpty)
    }
}