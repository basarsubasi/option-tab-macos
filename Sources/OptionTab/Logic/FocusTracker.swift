@preconcurrency import AppKit
@preconcurrency import ApplicationServices

/// Tracks window focus changes using AXObserver to maintain MRU order.
/// Installs an observer on each running app and updates MRUTracker when focus changes.
final class FocusTracker: @unchecked Sendable {
    private let tracker: MRUTracker
    private var observers: [pid_t: AXObserver] = [:]
    private var observerRefs: [pid_t: AXUIElement] = [:]
    private let queue = DispatchQueue(label: "com.optiontab.focustracker", attributes: .concurrent)

    init(tracker: MRUTracker) {
        self.tracker = tracker
    }

    /// Start tracking focus changes for all currently running apps
    /// and register for new app launch notifications.
    func start() {
        // Track existing apps
        for app in NSWorkspace.shared.runningApplications {
            trackApp(app)
        }

        // Listen for new apps launching
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidLaunch(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )

        // Listen for apps terminating
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidTerminate(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }

    /// Stop all observers and notifications.
    func stop() {
        NotificationCenter.default.removeObserver(self)
        queue.sync {
            for (_, observer) in self.observers {
                CFRunLoopRemoveSource(
                    CFRunLoopGetMain(),
                    AXObserverGetRunLoopSource(observer),
                    .defaultMode
                )
            }
            self.observers.removeAll()
            self.observerRefs.removeAll()
        }
    }

    // MARK: - Private

    private func trackApp(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }
        guard pid != 0 else { return }

        // Don't track apps without a UI
        guard app.activationPolicy != .prohibited else { return }

        queue.async(flags: .barrier) { [self] in
            self.installObserver(for: pid)
        }
    }

    private func installObserver(for pid: pid_t) {
        let appElement = AXUIElementCreateApplication(pid)

        // Context pointer for the callback
        let trackerRef = Unmanaged.passUnretained(tracker).toOpaque()

        var observer: AXObserver?
        let result = AXObserverCreate(pid, focusCallback, &observer)

        guard result == .success, let obs = observer else { return }

        // Add notification for focused window changes
        AXObserverAddNotification(obs, appElement, kAXFocusedWindowAttribute as CFString, trackerRef)

        // Add to run loop
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(obs),
            .defaultMode
        )

        observers[pid] = obs
        observerRefs[pid] = appElement
    }

    @objc private func appDidLaunch(_ notification: Notification) {
        guard let app = notification.userInfo?["NSApplication"] as? NSRunningApplication else {
            return
        }
        trackApp(app)
    }

    @objc private func appDidTerminate(_ notification: Notification) {
        guard let app = notification.userInfo?["NSApplication"] as? NSRunningApplication else {
            return
        }
        let pid = app.processIdentifier
        tracker.removeWindows(for: pid)

        queue.async(flags: .barrier) { [self] in
            if let observer = self.observers[pid] {
                CFRunLoopRemoveSource(
                    CFRunLoopGetMain(),
                    AXObserverGetRunLoopSource(observer),
                    .defaultMode
                )
                let appElement = self.observerRefs[pid] ?? AXUIElementCreateApplication(pid)
                AXObserverRemoveNotification(observer, appElement, kAXFocusedWindowAttribute as CFString)
                self.observers.removeValue(forKey: pid)
                self.observerRefs.removeValue(forKey: pid)
            }
        }
    }
}

// MARK: - AXObserver Callback

/// Global AXObserver callback. Called when a window gains focus.
private func focusCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    guard let refcon = refcon else { return }
    let tracker = Unmanaged<MRUTracker>.fromOpaque(refcon).takeUnretainedValue()

    // Get the focused window
    var windowValue: CFTypeRef?
    let windowResult = AXUIElementCopyAttributeValue(
        element,
        kAXFocusedWindowAttribute as CFString,
        &windowValue
    )

    if windowResult == .success, let axWindow = windowValue {
        // Try to get a CGWindowID by matching against the window list
        // Use PID-based matching since we can't directly extract CGWindowID from AXUIElement
        var pidValue: pid_t = 0
        let pidResult = AXUIElementGetPid(element, &pidValue)

        if pidResult == .success {
            // Look up the window by title in CGWindowListCopyWindowInfo
            var titleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow as! AXUIElement, kAXTitleAttribute as CFString, &titleValue)
            let title = (titleValue as? String) ?? ""

            let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
            if let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
                for dict in windowList {
                    if let winPID = dict[kCGWindowOwnerPID as String] as? pid_t,
                       winPID == pidValue,
                       let winID = dict[kCGWindowNumber as String] as? CGWindowID {
                        // Found a matching window
                        if title.isEmpty || (dict[kCGWindowName as String] as? String) == title {
                            tracker.updateFocus(windowID: winID)
                            return
                        }
                    }
                }
                // If no title match, update focus for the first window of this PID
                for dict in windowList {
                    if let winPID = dict[kCGWindowOwnerPID as String] as? pid_t,
                       winPID == pidValue,
                       let winID = dict[kCGWindowNumber as String] as? CGWindowID,
                       (dict[kCGWindowLayer as String] as? Int) == 0 {
                        tracker.updateFocus(windowID: winID)
                        return
                    }
                }
            }
        }
    }
}