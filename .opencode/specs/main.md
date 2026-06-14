# Main Spec: Option-Tab macOS

## Purpose

A lightweight macOS utility that provides a keyboard-driven window switcher — switching across **windows** (not just apps) — with a horizontal icon strip UI, MRU-based ordering, and menu bar presence.

## Goals

- Allow users to switch across individual windows (including minimized ones) on the current Space, not just across apps.
- Present a horizontal icon strip (no thumbnails) ordered by most-recently-used, starting from the second-most-recent window.
- Run as a menu bar agent app with no Dock icon.
- Provide a configurable global keyboard shortcut (default Opt+Tab).
- Support autostart on login via a toggle in the menu bar menu.
- Distribute as a DMG and Homebrew Cask.

## Non-Goals

- Thumbnail previews of windows — icons only.
- Cross-Space (virtual desktop) window switching — current Space only.
- Mac App Store distribution — the app requires Accessibility permissions and cannot be sandboxed.
- App icon badges, window counts, or any text overlays on icons.
- Multi-monitor awareness beyond the current Space.

## Use Cases

- **Quick window switching**: User presses the configured shortcut, sees a horizontal icon strip of recent windows, and cycles through them by repeating the shortcut or using arrow keys.
- **Minimized window restoration**: Minimized windows appear in the strip; selecting one unminimizes and focuses it.
- **Autostart management**: User toggles "Start at Login" from the menu bar icon; the app registers or unregisters itself as a login item.

## User Stories

- As a multi-window power user, I want to switch directly to a specific window regardless of which app owns it, so that I avoid the extra step of switching app then finding the right window.
- As a power user, I want minimized windows to appear in the switcher, so that I can restore them without reaching for the mouse.
- As a power user, I want the switcher to start from the second-most-recently-used window, so that a single shortcut press takes me to my last active window.
- As a user with custom keyboard preferences, I want to configure the switcher shortcut, so that it fits my workflow.
- As a daily user, I want the app to start at login, so that I never have to launch it manually.

## Domain Model / Terminology

- **Window**: An individual OS window (may belong to any app). Has a CGWindowID, a PID, an app icon, and an optional title.
- **MRU Order**: Most-recently-used order. The most recent window is the currently focused one; the switcher starts from the second entry.
- **Accessible Window**: A window that is either on-screen or minimized on the current Space.
- **Switcher**: The UI panel (horizontal icon strip) that appears when the shortcut is pressed.
- **Menu Bar Agent**: An app that runs with no Dock icon, using LSUIElement + `.accessory` activation policy.

## Architecture Principles

- **Swift + AppKit first**: Use Swift and AppKit for first-class macOS integration. No cross-platform UI frameworks.
- **No App Sandbox**: The app requires Accessibility API access (AXUIElement) which is incompatible with App Sandbox. Must be distributed outside the App Store.
- **Concurrent window tracking**: Use a background thread/queue to maintain the window list, avoiding blocking the main thread.
- **Minimal dependencies**: Prefer system frameworks (ApplicationServices, AppKit, ServiceManagement) over third-party libraries.
- **Test-driven**: Core logic (MRU tracking, window filtering, Space detection) should have unit tests written before or alongside implementation.

## UX / API Conventions

- Horizontal icon strip: left-to-right, MRU order (second-most-recent first).
- Highlighted icon indicates the window that will be activated on release.
- Releasing the modifier key activates the selected window.
- Arrow keys or repeated shortcut presses cycle through the strip.
- Menu bar menu provides: shortcut configuration, autostart toggle, and quit.
- First launch prompts for Accessibility permission if not already granted.

## Quality Standards

- Unit tests for MRU ordering, window filtering (current Space, minimized state), and shortcut handling logic.
- The switcher panel must appear within 100ms of the shortcut press, this and actual window switch is the main optimization points we need to consider.
- No more than 1% CPU usage while idle (no polling; event-driven updates).
- if asked permission is denied, stop working entirely

## Decision Log

- 2026-06-14: Use Opt+Tab as default shortcut, configurable via menu (user decision).
- 2026-06-14: Horizontal icon strip, not vertical (user decision, changed from vertical).
- 2026-06-14: Current Space only, no cross-Space switching (user decision).
- 2026-06-14: Menu bar only, no Dock icon (user decision).
- 2026-06-14: DMG + Homebrew Cask distribution (user decision).
- 2026-06-14: Swift + AppKit, no SwiftUI, no App Sandbox (architecture decision).
- 2026-06-14: Autostart on boot toggle via ServiceManagement framework (user decision).

## Open Questions

- Should the icon strip wrap around visually (loop) or stop at the ends? -> loop around
- Should the strip show the window title below the icon, or rely on icon + highlight only? -> show the window title as well.
- Should the app support a hidden toggle for all-Spaces mode in the future? -> no