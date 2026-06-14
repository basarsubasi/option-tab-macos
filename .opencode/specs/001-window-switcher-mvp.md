# Feature Spec: Window Switcher MVP

## Objective

Build a macOS menu-bar utility that lets users switch across individual windows (including minimized ones) on the current Space using a horizontal icon strip, with MRU ordering that starts from the second-most-recently-used window.

## Main Spec Alignment

Reference: `.opencode/specs/main.md`

Relevant sections:
- **Goals** — window-level switching, MRU ordering from second-most-recent, configurable shortcut, autostart toggle.
- **Architecture Principles** — Swift + AppKit, no App Sandbox, concurrent window tracking, minimal dependencies.
- **UX / API Conventions** — horizontal icon strip, highlight + release to activate, menu bar menu.
- **Quality Standards** — ≤100ms panel appearance, ≤1% idle CPU, unit tests for core logic.

## Background

macOS's built-in Cmd+Tab switcher operates at the app level, not the window level. Users with many windows across apps need a utility that switches directly to a specific window. The existing open-source project `lwouis/alt-tab-macos` demonstrates that `CGWindowListCopyWindowInfo` + `AXUIElement` is the correct approach for window enumeration and MRU tracking, but our project is simpler: no thumbnails, icons only.

Key APIs:
- `CGWindowListCopyWindowInfo` — on-screen windows, layer 0 filter
- `AXUIElement` — minimized windows, window titles, raise/focus actions, MRU tracking via `AXObserver`
- `NSRunningApplication.icon` — app icons (system-cached)
- `CGEvent.tap` — global hotkey interception
- `ServiceManagement` / `SMAppService` — login item management
- `NSWorkspace.didChangeActiveSpaceNotification` — Space change detection

## Requirements

### R1: Menu Bar Agent Lifecycle
- The app runs as a menu bar agent with no Dock icon (LSUIElement + `.accessory` activation policy).
- On first launch, prompt for Accessibility permission if not granted.
- The menu bar menu provides: shortcut configuration, autostart toggle, and quit.

### R2: Window Enumeration
- Enumerate all accessible windows (on-screen + minimized) on the current Space using a concurrent background queue.
- Filter out system windows (layer ≠ 0), the switcher's own window, and windows from other Spaces.
- On-screen windows: use `CGWindowListCopyWindowInfo`.
- Minimized windows: query each app's `AXUIElement` windows where `kAXMinimizedAttribute == true`.
- Merge both lists, deduplicating by `CGWindowID`.

### R3: MRU Order Tracking
- Track window focus changes using `AXObserver` on each running app.
- Record the timestamp of each focus event per window.
- Sort accessible windows by descending focus timestamp (most recent first).
- The currently focused window is always position 0; the switcher starts selection at position 1 (second-most-recent).

### R4: Horizontal Icon Strip UI
- Display a horizontal row of app icons representing windows in MRU order.
- The selected window is highlighted (border or background).
- Releasing the modifier key activates the highlighted window.
- Pressing the shortcut again (or arrow keys) cycles the highlight left-to-right.
- Wrapping: cycling past the last item wraps to the first (position 1, not position 0).

### R5: Window Activation
- On selection: if minimized, unminimize via `AXUIElementSetAttributeValue(kAXMinimizedAttribute, false)`.
- Raise the window via `AXUIElementPerformAction(kAXRaiseAction)`.
- Activate the owning app via `NSRunningApplication.activate(options: .activateIgnoringOtherApps)`.
- If Accessibility permission is missing, gracefully fall back to on-screen windows only (no minimize/restore).

### R6: Configurable Global Shortcut
- Default shortcut: Opt+Tab.
- User can reconfigure the shortcut from the menu bar menu.
- Intercept the shortcut globally using `CGEvent.tap` at `kCGHIDEventTap`.
- The shortcut is a modifier + key combination; modifier pressed = show strip; modifier released = activate selection.

### R7: Autostart on Login
- Provide a "Start at Login" toggle in the menu bar menu.
- Use `SMAppService` (macOS 13+) to register/unregister as a login item.
- The toggle reflects the current registration state.

## Non-Goals

- Thumbnail previews of any kind.
- Cross-Space (virtual desktop) window switching.
- App Store distribution.
- Window titles in the strip (icons only for MVP).
- Drag-and-drop reordering of windows in the strip.
- Window management features (resize, tile, move to Space).

## Use Cases

- **Scenario: Quick switch to last window**
  - User presses Opt+Tab (or configured shortcut).
  - Strip appears with the second-most-recent window highlighted.
  - User releases modifier → that window is activated.

- **Scenario: Cycle through windows**
  - User presses Opt+Tab, strip appears.
  - User presses Tab again (while holding modifier) → highlight moves to next window.
  - User releases modifier → highlighted window is activated.

- **Scenario: Restore minimized window**
  - Minimized window appears in the strip with its app icon.
  - User selects it → window unminimizes and comes to foreground.

- **Scenario: Reconfigure shortcut**
  - User clicks menu bar icon → Preferences → Shortcut.
  - User presses new key combination → shortcut is saved.
  - New shortcut takes effect immediately.

- **Scenario: Enable autostart**
  - User clicks menu bar icon → "Start at Login" toggle.
  - App registers login item via SMAppService.
  - Next login, app launches automatically.

- **Scenario: First launch without Accessibility**
  - App detects missing Accessibility permission.
  - Prompts user to grant it in System Settings.
  - In the meantime, shows on-screen windows only (no minimized windows, no window titles).

## User Stories

- As a power user, I want to press a single shortcut to jump to my last-used window, so that I can switch rapidly without mouse.
- As a multi-window user, I want to cycle through all my windows (including minimized), so that I never lose a window.
- As a user with custom keyboard preferences, I want to rebind the switcher shortcut, so that it fits my existing muscle memory.
- As a daily user, I want the app to start at login, so that it's always available.
- As a first-time user, I want a clear prompt to grant Accessibility access, so that all features work.

## Acceptance Criteria

- **AC1**: Given the app is running and Accessibility is granted, when the user presses the configured shortcut, then a horizontal icon strip appears within 100ms showing all accessible windows on the current Space in MRU order.
- **AC2**: Given the strip is visible and the second-most-recent window is highlighted, when the user releases the modifier key, then that window is activated and focused.
- **AC3**: Given the strip is visible, when the user presses the shortcut key again (or arrow key) while holding the modifier, then the highlight advances to the next window; cycling past the end wraps to the beginning.
- **AC4**: Given a target window is minimized, when the user selects it in the strip, then the window is unminimized and brought to the foreground.
- **AC5**: Given Accessibility is not granted, when the user opens the switcher, then only on-screen windows appear (no minimized windows, no window titles for other apps).
- **AC6**: Given the user opens Preferences from the menu bar, when they press a new key combination for the shortcut, then the shortcut is reconfigured immediately.
- **AC7**: Given the user toggles "Start at Login" on, when they log in next time, then the app launches automatically.
- **AC8**: Given the user toggles "Start at Login" off, then the login item is removed and the app no longer auto-launches.
- **AC9**: Given the app has been idle with no user interaction, then CPU usage remains ≤1%.

## Edge Cases

- **No accessible windows**: Strip shows empty or a "No windows" message; shortcut does nothing visible.
- **Only one window**: Strip shows that one window; activation is a no-op (already focused).
- **All windows minimized**: All appear in the strip; selecting any one unminimizes it.
- **Window closes while strip is visible**: Strip updates immediately to remove the closed window.
- **App quits while tracked**: Remove all its windows from the MRU list.
- **Space change while app is running**: Re-filter windows for the current Space; strip reflects current Space only.
- **Accessibility permission revoked mid-session**: Fall back to on-screen-only mode; show a notification.
- **CGEvent tap fails (no Accessibility)**: Cannot intercept shortcut; show a prompt to grant Accessibility.

## Test Strategy

- **Unit tests** (XCTest, TDD):
  - MRU ordering: verify sort by timestamp, second-most-recent starts selected.
  - Window filtering: on-screen (layer 0), minimized inclusion, current Space only, deduplication.
  - Shortcut registration: verify default shortcut, reconfiguration, storage.
  - Autostart toggle: verify SMAppService register/unregister calls.
- **Integration tests**:
  - Window enumeration: mock CGWindowList + AXUIElement data, verify merged list.
  - Focus event tracking: simulate AXObserver notifications, verify MRU update.
- **Manual verification**:
  - Switcher panel appears within 100ms of shortcut press.
  - Window activation (focus, unminimize) works correctly.
  - Menu bar menu: shortcut config, autostart toggle, quit all functional.
  - First-launch Accessibility prompt flow.
  - CPU usage ≤1% while idle (Activity Monitor).

## Implementation Notes

- Use `NSPanel` (borderless, floating, non-activating) for the switcher overlay.
- Use `CGEvent.tap` at `kCGHIDEventTap` for global hotkey interception.
- Use `AXObserver` per running app to track focus changes for MRU.
- Use `DispatchQueue.global(qos: .userInitiated)` for window enumeration to avoid blocking main thread.
- Use `SMAppService.mainApp` (macOS 13+) for login item registration.
- Target macOS 13+ (Ventura) for SMAppService availability.
- Project structure: Swift Package Manager or Xcode project with SwiftUI/AppKit.

## Open Questions

- Should icons in the strip show a tooltip with the window title on hover?
- Should the strip have a maximum number of visible icons before scrolling?
- What should the default strip width/height be? Should it scale with number of windows?