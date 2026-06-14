# OptionTab

OptionTab is a fast and minimal window switcher that fixes the most annoying shortcomings of the default macOS Cmd+Tab switcher. No notifications, no premium only features, no update pop-ups, no bullshit.

## Features
- **Quiet by design**: No annoying notifications or pop-ups whatsoever.
- **Free as in free beer**: This app is completely free to use and will stay free forever.
- **Stable as you can get**: Targeting the most stable macOS APIs as possible, meaning you probably won't need to update this app very often if ever.
- **Smart Window Ordering**: Switches to most recently used windows first.
- **Keyboard Navigation**: Cycle through windows using customizable keyboard shortcuts.
- **Mouse Support**: You can use your mouse to switch windows as well as the keyboard shortcut.
- **Lightweight & Fast**: Built as a native Swift project with zero unnecessary bloat and third party dependencies.
- **Theme Support**: Choose between light or dark themes or use your system theme.

---

## Installation

You can download the latest pre-compiled version of OptionTab directly from GitHub.

1. Go to the **Releases** page of this repository and download the latest `OptionTab.dmg` file.
2. Double-click the `.dmg` file to open it.
3. Drag `OptionTab.app` into your **Applications** folder.

### Important: macOS Gatekeeper Bypass

Because OptionTab is an indie open-source project, it is not signed with a paid Apple Developer certificate. When you download it through a web browser, macOS will automatically quarantine the app. If you try to open it, you may see a scary (and misleading) error stating:
> *"OptionTab is damaged and can't be opened. You should move it to the Trash."*

**To fix this and allow the app to run permanently, you must manually remove the quarantine flag.**

After dragging the app to your Applications folder, open your **Terminal** and run this exact command:
```bash
xattr -cr /Applications/OptionTab.app
```
Once you run this command, the security block is permanently lifted, and you can launch OptionTab normally.

---

## Permissions Required

Upon first launch, macOS will prompt you to grant OptionTab **Accessibility** permissions. 

This is strictly required. OptionTab uses Apple's Accessibility APIs to:
1. Detect which windows are currently open across all your apps.
2. Capture your custom keyboard shortcuts globally.
3. Bring the selected window to the front when you switch to it.

To grant access: Go to **System Settings** → **Privacy & Security** → **Accessibility** and turn the switch ON for OptionTab.

---

## Building from Source

If you prefer to compile OptionTab yourself, it's incredibly easy:

1. Clone this repository.
2. To build a local development version, run:
   ```bash
   ./build_app.sh
   ```
3. To package a full release `.dmg`, run:
   ```bash
   ./create-dmg.sh
   ```
