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

        // Container with rounded background
        let containerView = NSView()
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95).cgColor
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
            let wrapper = NSView()
            wrapper.wantsLayer = true
            wrapper.layer?.cornerRadius = 12
            wrapper.layer?.masksToBounds = true
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