import Testing
import Carbon
@testable import OptionTab

final class HotkeyManagerTests {

    @Test("Default shortcut is Option+Tab")
    func testDefaultShortcut() {
        let shortcut = HotkeyManager.Shortcut.defaultShortcut
        #expect(shortcut.keyCode == UInt32(kVK_Tab))
        #expect(shortcut.modifierFlags == UInt32(optionKey))
    }

    @Test("Shortcut display string for default shortcut contains Option and Tab")
    func testDefaultShortcutDisplayString() {
        let shortcut = HotkeyManager.Shortcut.defaultShortcut
        let display = shortcut.displayString
        #expect(display.contains("\u{2325}"))  // ⌥
        #expect(display.contains("Tab"))
    }

    @Test("Shortcut display string for Cmd+Tab contains Command symbol")
    func testCmdTabDisplayString() {
        let shortcut = HotkeyManager.Shortcut(
            keyCode: UInt32(kVK_Tab),
            modifierFlags: UInt32(cmdKey)
        )
        let display = shortcut.displayString
        #expect(display.contains("\u{2318}"))  // ⌘
        #expect(display.contains("Tab"))
    }

    @Test("Shortcut display string for Ctrl+Opt+S shows both modifiers")
    func testComplexShortcutDisplayString() {
        let shortcut = HotkeyManager.Shortcut(
            keyCode: UInt32(kVK_ANSI_S),
            modifierFlags: UInt32(controlKey) | UInt32(optionKey)
        )
        let display = shortcut.displayString
        #expect(display.contains("\u{2303}"))  // ⌃
        #expect(display.contains("\u{2325}"))  // ⌥
        #expect(display.contains("S"))
    }

    @Test("Shortcut is saved and loaded from UserDefaults")
    func testShortcutPersistence() {
        let shortcut = HotkeyManager.Shortcut(
            keyCode: UInt32(kVK_ANSI_S),
            modifierFlags: UInt32(controlKey) | UInt32(shiftKey)
        )

        let encoded = try? JSONEncoder().encode(shortcut)
        #expect(encoded != nil)

        UserDefaults.standard.set(encoded, forKey: "HotkeyManagerTests.shortcut")

        if let data = UserDefaults.standard.data(forKey: "HotkeyManagerTests.shortcut"),
           let decoded = try? JSONDecoder().decode(HotkeyManager.Shortcut.self, from: data) {
            #expect(decoded.keyCode == shortcut.keyCode)
            #expect(decoded.modifierFlags == shortcut.modifierFlags)
        } else {
            Issue.record("Failed to decode shortcut from UserDefaults")
        }

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "HotkeyManagerTests.shortcut")
    }

    @Test("KeyCode to string mapping for special keys")
    func testKeyCodeToString() {
        let tab = HotkeyManager.Shortcut(keyCode: UInt32(kVK_Tab), modifierFlags: 0)
        #expect(tab.displayString.contains("Tab"))

        let escape = HotkeyManager.Shortcut(keyCode: UInt32(kVK_Escape), modifierFlags: 0)
        #expect(escape.displayString.contains("Esc"))

        let space = HotkeyManager.Shortcut(keyCode: UInt32(kVK_Space), modifierFlags: 0)
        #expect(space.displayString.contains("Space"))
    }

    @Test("Equality compares by CGWindowID")
    func testWindowItemEquality() {
        let w1 = WindowItem(
            id: 42, pid: 1000, appName: "Safari", title: "Google",
            bounds: .zero, isMinimized: false, appIcon: nil, lastFocusTime: 100
        )
        let w2 = WindowItem(
            id: 42, pid: 2000, appName: "Terminal", title: "Different",
            bounds: .zero, isMinimized: true, appIcon: nil, lastFocusTime: 200
        )
        // Same CGWindowID means equal regardless of other fields
        #expect(w1 == w2)
    }

    @Test("Different CGWindowIDs mean unequal WindowItems")
    func testWindowItemInequality() {
        let w1 = WindowItem(id: 1, pid: 1000, appName: "Safari", title: "", bounds: .zero, isMinimized: false, appIcon: nil, lastFocusTime: 0)
        let w2 = WindowItem(id: 2, pid: 1000, appName: "Safari", title: "", bounds: .zero, isMinimized: false, appIcon: nil, lastFocusTime: 0)
        #expect(w1 != w2)
    }
}