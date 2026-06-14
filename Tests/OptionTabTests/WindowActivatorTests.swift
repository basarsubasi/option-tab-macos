import Testing
@testable import OptionTab

final class WindowActivatorTests {

    // WindowActivator uses AXUIElement which requires Accessibility permissions
    // and real running apps, so we test the structural aspects here.
    // Full activation tests require manual verification.

    @Test("WindowItem equality is based on CGWindowID")
    func testWindowItemEquality() {
        let w1 = WindowItem(
            id: 42,
            pid: 1000,
            appName: "Safari",
            title: "Google",
            bounds: .zero,
            isMinimized: false,
            appIcon: nil,
            lastFocusTime: 100
        )
        let w2 = WindowItem(
            id: 42,
            pid: 2000,
            appName: "Terminal",
            title: "Different",
            bounds: .zero,
            isMinimized: true,
            appIcon: nil,
            lastFocusTime: 200
        )
        // Same CGWindowID means equal regardless of other fields
        #expect(w1 == w2)
    }

    @Test("WindowItem inequality for different IDs")
    func testWindowItemInequality() {
        let w1 = WindowItem(id: 1, pid: 1000, appName: "Safari", title: "", bounds: .zero, isMinimized: false, appIcon: nil, lastFocusTime: 0)
        let w2 = WindowItem(id: 2, pid: 1000, appName: "Safari", title: "", bounds: .zero, isMinimized: false, appIcon: nil, lastFocusTime: 0)
        #expect(w1 != w2)
    }

    @Test("WindowItem with different PIDs but same ID are equal")
    func testWindowItemSameIDDifferentPID() {
        let w1 = WindowItem(id: 99, pid: 1000, appName: "A", title: "", bounds: .zero, isMinimized: false, appIcon: nil, lastFocusTime: 0)
        let w2 = WindowItem(id: 99, pid: 2000, appName: "B", title: "", bounds: .zero, isMinimized: false, appIcon: nil, lastFocusTime: 0)
        #expect(w1 == w2)
    }
}