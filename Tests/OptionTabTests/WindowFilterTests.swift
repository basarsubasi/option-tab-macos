import Testing
import Foundation
import CoreGraphics
@testable import OptionTab

final class WindowFilterTests {

    private func makeWindowDict(
        windowID: CGWindowID,
        pid: pid_t = 1000,
        ownerName: String = "TestApp",
        title: String = "Test Window",
        layer: Int = 0,
        bounds: [String: CGFloat] = ["X": 0.0, "Y": 0.0, "Width": 800.0, "Height": 600.0]
    ) -> [String: Any] {
        return [
            kCGWindowNumber as String: windowID,
            kCGWindowOwnerPID as String: pid,
            kCGWindowOwnerName as String: ownerName,
            kCGWindowName as String: title,
            kCGWindowLayer as String: layer,
            kCGWindowBounds as String: bounds,
        ]
    }

    private func makeWindowItem(
        id: CGWindowID,
        pid: pid_t = 1000,
        appName: String = "TestApp",
        title: String = "Test Window",
        isMinimized: Bool = false
    ) -> WindowItem {
        WindowItem(
            id: id,
            pid: pid,
            appName: appName,
            title: title,
            bounds: .zero,
            isMinimized: isMinimized,
            appIcon: nil,
            lastFocusTime: 0
        )
    }

    // MARK: - filterOnScreenWindows tests

    @Test("WindowFilter excludes windows with layer != 0")
    func testFilterExcludesNonZeroLayer() {
        let layer1 = makeWindowDict(windowID: 1, layer: 1)
        let layer0 = makeWindowDict(windowID: 2, layer: 0)

        let result = WindowFilter.filterOnScreenWindows(from: [layer1, layer0], ownPID: 9999)
        #expect(result.count == 1)
        #expect(result[0].id == 2)
    }

    @Test("WindowFilter excludes own app windows")
    func testFilterExcludesOwnApp() {
        let ownPID: pid_t = 12345
        let ownWindow = makeWindowDict(windowID: 1, pid: ownPID)
        let otherWindow = makeWindowDict(windowID: 2, pid: 1000)

        let result = WindowFilter.filterOnScreenWindows(from: [ownWindow, otherWindow], ownPID: ownPID)
        #expect(result.count == 1)
        #expect(result[0].pid == 1000)
    }

    @Test("WindowFilter excludes Dock and Window Server")
    func testFilterExcludesDockAndWindowServer() {
        let dockWindow = makeWindowDict(windowID: 1, ownerName: "Dock")
        let windowServerWindow = makeWindowDict(windowID: 2, ownerName: "Window Server")
        let normalWindow = makeWindowDict(windowID: 3, ownerName: "Safari")

        let result = WindowFilter.filterOnScreenWindows(from: [dockWindow, windowServerWindow, normalWindow], ownPID: 9999)
        #expect(result.count == 1)
        #expect(result[0].appName == "Safari")
    }

    @Test("WindowFilter passes valid windows through")
    func testFilterPassesValidWindows() {
        let w1 = makeWindowDict(windowID: 1, ownerName: "Safari")
        let w2 = makeWindowDict(windowID: 2, ownerName: "Terminal")

        let result = WindowFilter.filterOnScreenWindows(from: [w1, w2], ownPID: 9999)
        #expect(result.count == 2)
    }

    // MARK: - mergeMinimizedWindows tests

    @Test("mergeMinimizedWindows deduplicates by CGWindowID")
    func testMergeDeduplicates() {
        let onScreen = [
            makeWindowItem(id: 1, isMinimized: false),
            makeWindowItem(id: 2, isMinimized: false),
        ]
        let minimized = [
            makeWindowItem(id: 2, isMinimized: true),  // duplicate ID
            makeWindowItem(id: 3, isMinimized: true),
        ]

        let result = WindowFilter.mergeMinimizedWindows(onScreen: onScreen, minimized: minimized)
        #expect(result.count == 3)  // 2 on-screen + 1 unique minimized
        #expect(result.filter { $0.isMinimized }.count == 1)
    }

    @Test("mergeMinimizedWindows adds all minimized when no overlap")
    func testMergeNoOverlap() {
        let onScreen = [
            makeWindowItem(id: 1, isMinimized: false),
        ]
        let minimized = [
            makeWindowItem(id: 2, isMinimized: true),
            makeWindowItem(id: 3, isMinimized: true),
        ]

        let result = WindowFilter.mergeMinimizedWindows(onScreen: onScreen, minimized: minimized)
        #expect(result.count == 3)
    }

    // MARK: - filterForCurrentSpace tests

    @Test("filterForCurrentSpace includes minimized when Accessibility granted")
    func testFilterIncludesMinimizedWithAccessibility() {
        let windows = [
            makeWindowItem(id: 1, isMinimized: false),
            makeWindowItem(id: 2, isMinimized: true),
        ]

        let result = WindowFilter.filterForCurrentSpace(windows: windows, accessibilityGranted: true)
        #expect(result.count == 2)
    }

    @Test("filterForCurrentSpace excludes minimized when Accessibility not granted")
    func testFilterExcludesMinimizedWithoutAccessibility() {
        let windows = [
            makeWindowItem(id: 1, isMinimized: false),
            makeWindowItem(id: 2, isMinimized: true),
        ]

        let result = WindowFilter.filterForCurrentSpace(windows: windows, accessibilityGranted: false)
        #expect(result.count == 1)
        #expect(result[0].isMinimized == false)
    }
}