import AppKit

/// The horizontal icon strip panel that appears when the shortcut is pressed.
@MainActor
final class SwitcherPanel: NSPanel {
    private var windows: [WindowItem] = []
    private var selectedIndex = 0
    private var iconViews: [NSImageView] = []
    private var wrapperViews: [NSView] = [] // Track wrappers for highlighting
    private let mainStackView = NSStackView()
    private let gridStackView = NSStackView() // Vertical stack for rows
    private let titleLabel = NSTextField(labelWithString: "")
    
    var onCloseWindow: ((WindowItem) -> Void)?
    var onSelectWindow: ((WindowItem) -> Void)?
    
    private let maxColumns = 8

    // Highlight configuration
    private let iconSize: CGFloat = 64
    private let iconPadding: CGFloat = 16
    private let highlightBorderWidth: CGFloat = 4
    private let highlightColor: NSColor = .controlAccentColor
    private let panelPadding: CGFloat = 48

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        setupStackView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public

    /// Show the panel with the given windows, starting selection at index 1 (second-most-recent).
    func show(with windows: [WindowItem]) {
        self.windows = windows
        self.selectedIndex = windows.count > 1 ? 1 : 0

        rebuildIconViews()

        guard !windows.isEmpty else {
            // Show empty state
            titleLabel.stringValue = "No windows"
            gridStackView.subviews.forEach { $0.removeFromSuperview() }
            return
        }

        updateHighlight()

        // Position centered on screen
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            
            let columns = min(windows.count, maxColumns)
            let rows = Int(ceil(Double(windows.count) / Double(maxColumns)))
            
            let gridWidth = CGFloat(columns) * iconSize + CGFloat(max(0, columns - 1)) * iconPadding
            let gridHeight = CGFloat(rows) * iconSize + CGFloat(max(0, rows - 1)) * iconPadding
            
            let panelWidth = max(300, gridWidth + panelPadding * 2)
            let panelHeight = gridHeight + panelPadding * 2 + 36 // Extra 36 for title label
            
            let x = frame.midX - panelWidth / 2
            let y = frame.midY - panelHeight / 2
            setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
        }

        orderFrontRegardless()
    }

    /// Hide the panel.
    func hide() {
        orderOut(nil)
        windows = []
        iconViews = []
        selectedIndex = 0
    }

    /// Remove a window from the switcher dynamically.
    func removeWindow(withId id: CGWindowID) {
        if let index = windows.firstIndex(where: { $0.id == id }) {
            windows.remove(at: index)
            if selectedIndex >= windows.count {
                selectedIndex = max(0, windows.count - 1)
            }
            if windows.isEmpty {
                hide()
            } else {
                rebuildIconViews()
                updateHighlight()
                // Update size without losing center
                if let screen = NSScreen.main {
                    let frame = screen.visibleFrame
                    let columns = min(windows.count, maxColumns)
                    let rows = Int(ceil(Double(windows.count) / Double(maxColumns)))
                    
                    let gridWidth = CGFloat(columns) * iconSize + CGFloat(max(0, columns - 1)) * iconPadding
                    let gridHeight = CGFloat(rows) * iconSize + CGFloat(max(0, rows - 1)) * iconPadding
                    
                    let panelWidth = max(300, gridWidth + panelPadding * 2)
                    let panelHeight = gridHeight + panelPadding * 2 + 36
                    
                    let x = frame.midX - panelWidth / 2
                    let y = frame.midY - panelHeight / 2
                    setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
                }
            }
        }
    }

    /// Cycle the selection to the next window.
    func cycleNext() {
        guard !windows.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % windows.count
        updateHighlight()
    }

    /// Cycle the selection to the previous window.
    func cyclePrevious() {
        guard !windows.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + windows.count) % windows.count
        updateHighlight()
    }

    /// Get the currently selected window.
    var selectedWindow: WindowItem? {
        guard !windows.isEmpty && selectedIndex < windows.count else { return nil }
        return windows[selectedIndex]
    }

    // MARK: - Private

    private func setupStackView() {
        mainStackView.orientation = .vertical
        mainStackView.alignment = .centerX
        mainStackView.spacing = 8
        mainStackView.edgeInsets = NSEdgeInsets(
            top: panelPadding,
            left: panelPadding,
            bottom: panelPadding,
            right: panelPadding
        )

        gridStackView.orientation = .vertical
        gridStackView.alignment = .centerX
        gridStackView.spacing = iconPadding

        titleLabel.textColor = .labelColor
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        mainStackView.addArrangedSubview(gridStackView)
        mainStackView.addArrangedSubview(titleLabel)

        // Container with rounded blurred background (NSVisualEffectView handles themes automatically)
        let containerView = NSVisualEffectView()
        containerView.material = .popover
        containerView.blendingMode = .behindWindow
        containerView.state = .active
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 18
        containerView.layer?.masksToBounds = true

        containerView.addSubview(mainStackView)

        // Layout mainStackView to fill container
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mainStackView.topAnchor.constraint(equalTo: containerView.topAnchor),
            mainStackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            mainStackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            mainStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        ])

        self.contentView = containerView
    }

    private func rebuildIconViews() {
        gridStackView.subviews.forEach { $0.removeFromSuperview() }
        iconViews = []
        wrapperViews = []
        
        var currentHorizontalStack: NSStackView? = nil

        for window in windows {
            let icon = window.appIcon ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: "Unknown app")!
            let resizedIcon = resizeIcon(icon, to: NSSize(width: iconSize, height: iconSize))

            let imageView = NSImageView()
            imageView.image = resizedIcon
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.wantsLayer = true
            imageView.layer?.cornerRadius = (iconSize + highlightBorderWidth * 2) / 2 * 0.2
            imageView.layer?.masksToBounds = true

            imageView.translatesAutoresizingMaskIntoConstraints = false

            // Wrapper for highlight border
            let wrapper = HoverWrapperView()
            wrapper.windowItem = window
            wrapper.onClose = { [weak self] item in
                self?.onCloseWindow?(item)
            }
            wrapper.onClick = { [weak self] item in
                self?.onSelectWindow?(item)
            }
            wrapper.onHover = { [weak self] item in
                guard let self = self else { return }
                if let index = self.windows.firstIndex(where: { $0.id == item.id }) {
                    if self.selectedIndex != index {
                        self.selectedIndex = index
                        self.updateHighlight()
                    }
                }
            }
            wrapper.wantsLayer = true
            wrapper.layer?.cornerRadius = 12
            // We set masksToBounds false so the close button can slightly overlap the border if we wanted,
            // but we need the background color to respect the corner radius. 
            // We can just rely on cornerRadius applying to the background.
            wrapper.layer?.masksToBounds = false
            wrapper.translatesAutoresizingMaskIntoConstraints = false

            wrapper.addSubview(imageView)
            NSLayoutConstraint.activate([
                wrapper.widthAnchor.constraint(equalToConstant: iconSize + highlightBorderWidth * 2),
                wrapper.heightAnchor.constraint(equalToConstant: iconSize + highlightBorderWidth * 2),
                imageView.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: iconSize),
                imageView.heightAnchor.constraint(equalToConstant: iconSize),
            ])

            // Add close button
            let closeBtn = NSButton()
            closeBtn.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
            closeBtn.isBordered = false
            closeBtn.imagePosition = .imageOnly
            closeBtn.target = wrapper
            closeBtn.action = #selector(HoverWrapperView.closeClicked)
            closeBtn.translatesAutoresizingMaskIntoConstraints = false
            closeBtn.alphaValue = 0.0
            closeBtn.contentTintColor = .systemRed

            wrapper.addSubview(closeBtn)
            wrapper.closeButton = closeBtn

            NSLayoutConstraint.activate([
                closeBtn.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 4),
                closeBtn.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -4),
                closeBtn.widthAnchor.constraint(equalToConstant: 18),
                closeBtn.heightAnchor.constraint(equalToConstant: 18)
            ])

            // Minimized indicator: dim the icon
            if window.isMinimized {
               imageView.contentTintColor = .secondaryLabelColor
            }
            
            wrapperViews.append(wrapper)
            iconViews.append(imageView)
            
            if iconViews.count % maxColumns == 1 || maxColumns == 1 {
                currentHorizontalStack = NSStackView()
                currentHorizontalStack?.orientation = .horizontal
                currentHorizontalStack?.alignment = .centerY
                currentHorizontalStack?.spacing = iconPadding
                gridStackView.addArrangedSubview(currentHorizontalStack!)
            }
            currentHorizontalStack?.addArrangedSubview(wrapper)
        }
    }

    private func updateHighlight() {
        for (index, wrapper) in wrapperViews.enumerated() {
            guard index < iconViews.count else { break }

            if index == selectedIndex {
                wrapper.layer?.borderColor = highlightColor.cgColor
                wrapper.layer?.borderWidth = highlightBorderWidth
                wrapper.layer?.backgroundColor = highlightColor.withAlphaComponent(0.1).cgColor
            } else {
                wrapper.layer?.borderColor = NSColor.separatorColor.cgColor
                wrapper.layer?.borderWidth = 1
                wrapper.layer?.backgroundColor = NSColor.clear.cgColor
            }
        }
        
        if let selected = selectedWindow {
            if selected.title.isEmpty {
                titleLabel.stringValue = selected.appName
            } else {
                titleLabel.stringValue = "\(selected.appName) - \(selected.title)"
            }
        } else {
            titleLabel.stringValue = ""
        }
    }

    private func resizeIcon(_ icon: NSImage, to size: NSSize) -> NSImage {
        let resized = NSImage(size: size)
        resized.lockFocus()
        icon.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: icon.size),
            operation: .copy,
            fraction: 1.0
        )
        resized.unlockFocus()
        return resized
    }
}

private class HoverWrapperView: NSView {
    var closeButton: NSButton!
    var windowItem: WindowItem!
    var onClose: ((WindowItem) -> Void)?
    var onClick: ((WindowItem) -> Void)?
    var onHover: ((WindowItem) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            closeButton.animator().alphaValue = 1.0
        }
        onHover?(windowItem)
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            closeButton.animator().alphaValue = 0.0
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        onClick?(windowItem)
    }
    
    @objc func closeClicked() {
        onClose?(windowItem)
    }
}