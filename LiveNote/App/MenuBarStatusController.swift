import AppKit
import SwiftUI

@MainActor
final class MenuBarStatusController: NSObject {
    private let viewModel: RecordingViewModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var hostingView: PassthroughHostingView<MenuBarCapsuleLabel>?

    init(viewModel: RecordingViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: MenuBarStatusMetrics.statusItemLength)
        self.statusItem.autosaveName = "LiveNote.StatusCapsule"
        super.init()
    }

    func install() {
        guard let button = statusItem.button else {
            return
        }

        button.title = ""
        button.image = nil
        button.isBordered = false
        if let buttonCell = button.cell as? NSButtonCell {
            buttonCell.highlightsBy = []
            buttonCell.showsStateBy = []
        }
        button.toolTip = "LiveNote"
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        if hostingView == nil {
            let hostingView = PassthroughHostingView(rootView: MenuBarCapsuleLabel(viewModel: viewModel))
            hostingView.onLayout = { [weak self, weak hostingView] in
                guard let hostingView else {
                    return
                }
                hostingView.updateCapsuleLayer()
                self?.updateStatusItemLength()
            }
            hostingView.configureCapsuleLayer()
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(hostingView)

            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 1),
                hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -1),
                hostingView.topAnchor.constraint(equalTo: button.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
            ])

            self.hostingView = hostingView
            updateStatusItemLength()
        }

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 380, height: 236)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarStatusView(viewModel: viewModel)
        )
    }

    @objc
    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
        sender.highlight(false)
    }

    private func updateStatusItemLength() {
        if abs(statusItem.length - MenuBarStatusMetrics.statusItemLength) > 0.5 {
            statusItem.length = MenuBarStatusMetrics.statusItemLength
        }
    }
}

@MainActor
private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    var onLayout: (() -> Void)?

    override var allowsVibrancy: Bool {
        false
    }

    func configureCapsuleLayer() {
        appearance = NSAppearance(named: .aqua)
        wantsLayer = true
        layer?.masksToBounds = true
        updateCapsuleLayer()
    }

    func updateCapsuleLayer() {
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = bounds.height / 2
        layer?.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    override func layout() {
        super.layout()
        updateCapsuleLayer()
        onLayout?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateCapsuleLayer()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
