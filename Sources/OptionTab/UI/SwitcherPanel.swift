import AppKit

/// The horizontal icon strip panel that appears when the shortcut is pressed.
@MainActor
final class SwitcherPanel: NSPanel {
    private var windows: [WindowItem] = []
    private var selectedIndex = 0
    private var iconViews: [NSImageView] = []
    private let mainStackView = NSStackView()
    private let iconStackView = NSStackView()
    private let titleLabel = NSTextField(labelWithString: "")

    // Highlight configuration
    private let iconSize: CGFloat = 48
    private let iconPadding: CGFloat = 8
    private let highlightBorderWidth: CGFloat = 3
    private let highlightColor: NSColor = .controlAccentColor
    private let panelPadding: CGFloat = 16

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
            iconStackView.subviews.forEach { $0.removeFromSuperview() }
            return
        }

        updateHighlight()

        // Position centered on screen
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let panelWidth = max(300, CGFloat(windows.count) * (iconSize + iconPadding * 2) + panelPadding * 2)
            let panelHeight = iconSize + iconPadding * 2 + panelPadding * 2 + 30 // Extra 30 for title label
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

        iconStackView.orientation = .horizontal
        iconStackView.alignment = .centerY
        iconStackView.spacing = iconPadding

        titleLabel.textColor = .labelColor
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        mainStackView.addArrangedSubview(iconStackView)
        mainStackView.addArrangedSubview(titleLabel)

        // Container with rounded background
        let containerView = NSView()
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95).cgColor
        containerView.layer?.cornerRadius = 12
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
        iconStackView.subviews.forEach { $0.removeFromSuperview() }
        iconViews = []

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
            let wrapper = NSView()
            wrapper.wantsLayer = true
            wrapper.layer?.cornerRadius = 8
            wrapper.layer?.masksToBounds = true

            wrapper.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: iconSize),
                imageView.heightAnchor.constraint(equalToConstant: iconSize),
            ])

            // Minimized indicator: dim the icon
            if window.isMinimized {
               imageView.contentTintColor = .secondaryLabelColor
            }

            iconStackView.addArrangedSubview(wrapper)
            iconViews.append(imageView)
        }
    }

    private func updateHighlight() {
        for (index, wrapper) in iconStackView.arrangedSubviews.enumerated() {
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