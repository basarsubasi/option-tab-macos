# Implementation Plan: Window Switcher MVP

**Spec**: `.opencode/specs/001-window-switcher-mvp.md`
**Main Spec**: `.opencode/specs/main.md`

## Builder Handoff

1. Scaffold an Xcode project (Swift/AppKit, macOS 13+) with SPM structure.
2. Implement core logic modules first (test-driven), then UI, then integration.
3. Each TODO maps to one or more acceptance criteria from the spec.
4. Run `xcodebuild test` after each code-bearing TODO.

## TODOs

### TODO 1: Scaffold Xcode project structure
**AC**: — (infrastructure)
Create the Xcode project with:
- `OptionTabApp.swift` — app entry point, `@main`, `NSApplicationDelegate`
- `AppDelegate.swift` — menu bar agent setup, Accessibility check
- `Info.plist` — `LSUIElement = true`
- Xcode project file targeting macOS 13+
- Test target `OptionTabTests`
**Verify**: `xcodebuild build` succeeds.

### TODO 2: Window model and MRU tracker (TDD)
**AC**: AC1, AC3 (MRU ordering, second-most-recent first, wrapping)
Create `WindowItem.swift` (model) and `MRUTracker.swift` (ordering logic).
- `WindowItem`: holds `CGWindowID`, `pid_t`, `title`, `bounds`, `isMinimized`, `appIcon`, `lastFocusTime`.
- `MRUTracker`: maintains sorted window list by `lastFocusTime` descending; `updateFocus(windowID:)`, `removeWindow(windowID:)`, `sortedWindows()` returns list starting from second-most-recent.
- Write XCTest cases first: test sort order, test second-most-recent selection, test wrapping, test removal.
**Verify**: `xcodebuild test` passes all MRUTracker tests.

### TODO 3: Window filter (TDD)
**AC**: AC1, AC5 (current Space, layer 0, dedup, fallback)
Create `WindowFilter.swift`.
- Filter `CGWindowListCopyWindowInfo` results to layer 0, exclude own window, exclude desktop/Dock.
- Merge minimized windows from `AXUIElement` queries.
- Deduplicate by `CGWindowID`.
- Filter to current Space (use `NSWorkspace` notifications or CGS private API).
- Fallback: if Accessibility not granted, return only on-screen windows.
- Write tests: test layer filter, test merge+dedup, test current Space filter, test fallback.
**Verify**: `xcodebuild test` passes all WindowFilter tests.

### TODO 4: Concurrent window enumerator
**AC**: AC1, AC9 (enumerate on background queue, ≤100ms, ≤1% idle CPU)
Create `WindowEnumerator.swift`.
- Dispatch window enumeration to `DispatchQueue.global(qos: .userInitiated)`.
- Call `CGWindowListCopyWindowInfo` + `AXUIElement` per-app on background queue.
- Deliver results to main queue via callback.
- Write tests: test concurrent delivery, test no blocking on main queue.
**Verify**: `xcodebuild test` passes all WindowEnumerator tests.

### TODO 5: AXObserver focus tracker
**AC**: AC1, AC3, AC9 (MRU updates via focus events, ≤1% idle CPU)
Create `FocusTracker.swift`.
- Subscribe to `AXObserver` notifications for `kAXFocusedWindowAttribute` on each running app.
- On focus change, call `MRUTracker.updateFocus(windowID:)`.
- On app launch/quit, add/remove observers.
- Write tests: test focus event updates MRU, test observer lifecycle.
**Verify**: `xcodebuild test` passes all FocusTracker tests.

### TODO 6: Window activator
**AC**: AC2, AC4, AC5 (activate, unminimize, raise, fallback)
Create `WindowActivator.swift`.
- Unminimize: `AXUIElementSetAttributeValue(kAXMinimizedAttribute, false)`.
- Raise: `AXUIElementPerformAction(kAXRaiseAction)`.
- Activate app: `NSRunningApplication.activate(options: .activateIgnoringOtherApps)`.
- Fallback if Accessibility denied: use `NSRunningApplication.activate()` only.
- Write tests: test activation sequence ordering, test fallback path.
**Verify**: `xcodebuild test` passes all WindowActivator tests.

### TODO 7: Global hotkey manager (CGEvent tap)
**AC**: AC1, AC6 (shortcut interception, configurable shortcut)
Create `HotkeyManager.swift`.
- Create `CGEvent.tap` at `kCGHIDEventTap` for modifier+key interception.
- Default shortcut: Opt+Tab.
- On modifier press: show switcher panel.
- On modifier release: activate selected window, hide panel.
- On repeated key press while modifier held: cycle selection.
- Store shortcut in `UserDefaults`.
- Reconfigurable from menu bar menu.
- Write tests: test event parsing, test shortcut matching, test default shortcut, test reconfiguration.
**Verify**: `xcodebuild test` passes all HotkeyManager tests.

### TODO 8: Switcher panel UI (NSPanel)
**AC**: AC1, AC3 (horizontal icon strip, highlight, cycling)
Create `SwitcherPanel.swift` (NSPanel, borderless, floating, non-activating).
- Horizontal NSStackView or custom view containing app icons.
- Highlight the selected icon (border/background).
- Cycling: advance highlight on key press, wrap around.
- Show/hide animation.
**Verify**: Manual — panel appears on Opt+Tab press, icons display, highlight cycles, correct window activates on release.

### TODO 9: Menu bar agent + Preferences UI
**AC**: AC6, AC7, AC8 (shortcut config, autostart toggle)
Create `MenuBarController.swift` and `PreferencesWindow.swift`.
- `NSStatusItem` with icon in menu bar.
- Menu: Preferences, Start at Login (toggle), Quit.
- Preferences window: shortcut recorder (NSResponder key capture).
- Start at Login: `SMAppService.mainApp.register()` / `.unregister()`.
- First launch: check Accessibility, prompt if not granted.
**Verify**: Manual — menu bar appears,preferences window opens,shortcut can be reconfigured, Start at Login toggle works.

### TODO 10: Integration and polish
**AC**: AC1–AC9 (all criteria end-to-end)
- Wire all modules together in `AppDelegate`.
- Handle edge cases: no windows, single window, all minimized, window closes while visible, Space change.
- Add Accessibility permission changed notification → re-enable full mode.
- Ensure app hides from Dock (LSUIElement + `.accessory`).
- Performance verification: ≤100ms panel appearance, ≤1% idle CPU.
**Verify**: Manual end-to-end test of all acceptance criteria.

### TODO 11: DMG build and Homebrew Cask recipe
**AC**: — (distribution)
- Create a Release scheme in Xcode.
- Add a `Makefile` or script to build and package a DMG.
- Write a Homebrew Cask formula file (template).
**Verify**: `xcodebuild archive` produces an app; DMG builds successfully.

## Success Checks

- All unit tests pass (`xcodebuild test`).
- Switcher panel appears ≤100ms after shortcut press.
- CPU idle ≤1% (Activity Monitor).
- Windows switch correctly (on-screen and minimized).
- Shortcut reconfiguration works.
- Start at Login toggle works.
- App runs as menu bar agent (no Dock icon).