import SwiftUI
import Observation
import AppKit
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

@MainActor
@main
final class KaraAppDelegate: NSObject, NSApplicationDelegate {
    private let appModel = KaraAppModel()
    private var statusItemController: MenuBarStatusItemController?
    private var keepAlivePanel: NSPanel?

    static func main() {
        let app = NSApplication.shared
        let delegate = KaraAppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("Kara keeps menu bar voice and IM listeners active")
        installKeepAlivePanel()

        let controller = MenuBarStatusItemController(appModel: appModel)
        controller.install()
        statusItemController = controller
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func installKeepAlivePanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .normal
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        panel.orderFront(nil)
        keepAlivePanel = panel
    }
}

@MainActor
private final class MenuBarStatusItemController: NSObject {
    private let appModel: KaraAppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: 132)
    private let popover = NSPopover()
    private var refreshTimer: Timer?

    init(appModel: KaraAppModel) {
        self.appModel = appModel
    }

    func install() {
        guard let button = statusItem.button else { return }

        button.title = ""
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.isBordered = false
        button.target = self
        button.action = #selector(togglePopover)

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 380, height: 560)
        popover.contentViewController = NSHostingController(
            rootView: KaraMenuPanel(appModel: appModel)
        )

        refreshStatusImage()
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshStatusImage()
            }
        }
        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc
    private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func refreshStatusImage() {
        statusItem.button?.image = MenuBarCapsuleImageRenderer.image(
            tool: appModel.menuBarTool,
            label: appModel.menuBarSessionLabel,
            isRecording: appModel.isRecording
        )
    }
}

// MARK: - Menu bar live activity

private enum MenuBarCapsuleImageRenderer {
    static func image(tool: AIToolType?, label: String, isRecording: Bool) -> NSImage {
        let size = NSSize(width: 132, height: 24)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high

        let outerRect = NSRect(x: 0, y: 0, width: size.width, height: size.height)
        NSColor(calibratedWhite: 1.0, alpha: 0.76).setFill()
        NSBezierPath(roundedRect: outerRect, xRadius: 12, yRadius: 12).fill()

        NSColor(calibratedWhite: 1.0, alpha: 0.72).setStroke()
        NSBezierPath(
            roundedRect: outerRect.insetBy(dx: 0.5, dy: 0.5),
            xRadius: 11.5,
            yRadius: 11.5
        ).stroke()

        NSColor(calibratedWhite: 0.0, alpha: 0.13).setStroke()
        NSBezierPath(
            roundedRect: outerRect.insetBy(dx: 0.35, dy: 0.35),
            xRadius: 11.65,
            yRadius: 11.65
        ).stroke()

        let iconFrame = NSRect(x: 5, y: 2, width: 20, height: 20)

        if let icon = tool?.brandIcon {
            let inset: CGFloat = tool?.baseTool == .codexCLI ? -1.2 : 1.8
            icon.draw(
                in: iconFrame.insetBy(dx: inset, dy: inset),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
        } else if let fallback = NSImage(systemSymbolName: tool?.iconSystemName ?? "sparkles", accessibilityDescription: nil) {
            NSColor(calibratedWhite: 1.0, alpha: 0.92).setFill()
            NSBezierPath(ovalIn: iconFrame).fill()

            fallback.isTemplate = false
            fallback.draw(
                in: iconFrame.insetBy(dx: 4, dy: 4),
                from: .zero,
                operation: .sourceOver,
                fraction: 0.58
            )
        }

        let sessionRect = NSRect(x: 31, y: 3, width: 96, height: 18)
        let sessionColor = isRecording
            ? NSColor(calibratedRed: 1.0, green: 0.92, blue: 0.90, alpha: 0.96)
            : NSColor(calibratedWhite: 1.0, alpha: 0.94)
        sessionColor.setFill()
        NSBezierPath(roundedRect: sessionRect, xRadius: 8, yRadius: 8).fill()

        NSColor(calibratedWhite: 0.0, alpha: 0.08).setStroke()
        NSBezierPath(roundedRect: sessionRect.insetBy(dx: 0.35, dy: 0.35), xRadius: 7.65, yRadius: 7.65).stroke()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingTail

        let font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedWhite: 0.10, alpha: 0.86),
            .paragraphStyle: paragraphStyle
        ]

        let textRect = sessionRect.insetBy(dx: 6, dy: 0)
        let lineHeight = font.ascender - font.descender
        let baselineOffset = (textRect.height - lineHeight) / 2 - font.descender - 0.5
        let drawRect = NSRect(
            x: textRect.minX,
            y: textRect.minY + baselineOffset,
            width: textRect.width,
            height: lineHeight
        )
        (label as NSString).draw(
            with: drawRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: attributes
        )

        image.isTemplate = false
        return image
    }
}

private struct LiveActivityStatusLabel: View {
    let appModel: KaraAppModel

    var body: some View {
        HStack(spacing: 7) {
            AgentIconView(tool: appModel.menuBarTool, size: 20, framed: true)

            Text(appModel.menuBarSessionLabel)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(minWidth: 70)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(sessionFill)
                )
        }
        .padding(.leading, 5)
        .padding(.trailing, 5)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(Color(red: 0.015, green: 0.015, blue: 0.016))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 0.5)
        )
        .frame(width: 128, height: 24)
    }

    private var sessionFill: Color {
        appModel.isRecording
            ? Color(red: 1.0, green: 0.86, blue: 0.84)
            : Color(red: 0.90, green: 0.84, blue: 0.81)
    }
}

private struct AgentIconView: View {
    let tool: AIToolType?
    let size: CGFloat
    var framed = false

    var body: some View {
        ZStack {
            if framed, tool?.brandIcon == nil {
                Circle()
                    .fill(Color(red: 0.94, green: 0.89, blue: 0.86))
            }

            if let icon = tool?.brandIcon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .padding(tool?.baseTool == .codexCLI ? 0 : (framed ? size * 0.04 : 0))
            } else {
                Image(systemName: tool?.iconSystemName ?? "sparkles")
                    .font(.system(size: framed ? size * 0.62 : size, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary.opacity(framed ? 0.72 : 0.45))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Menu panel

private struct KaraMenuPanel: View {
    @Bindable var appModel: KaraAppModel

    var body: some View {
        VStack(spacing: 0) {
            panelHeader

            Divider()

            SettingsPanelView(
                aiService: appModel.aiService,
                imService: appModel.imService,
                taskService: appModel.taskService
            )

            Divider()

            HStack {
                Text("按住 Option 说话，松开停止")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("退出 Kara") {
                    NSApplication.shared.terminate(nil)
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private var panelHeader: some View {
        HStack(spacing: 10) {
            AgentIconView(tool: appModel.menuBarTool, size: 28, framed: true)

            VStack(alignment: .leading, spacing: 2) {
                Text(appModel.menuBarTool?.compactDisplayName ?? "未选择 Agent")
                    .font(.callout.weight(.semibold))

                if appModel.isRecording {
                    Text("正在收音，松开发送")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text(appModel.aiService.statusDetailText)
                        .font(.caption)
                        .foregroundStyle(statusDetailColor)
                }
            }

            Spacer()

            Image(systemName: appModel.isRecording ? "record.circle.fill" : "mic")
                .foregroundStyle(appModel.isRecording ? .red : .secondary)
                .symbolRenderingMode(.hierarchical)
                .font(.title3)
        }
        .padding(14)
    }

    private var statusDetailColor: Color {
        if case .failed = appModel.aiService.deliveryState {
            return .red
        }
        return .secondary
    }
}

// MARK: - App Model

@MainActor
@Observable
final class KaraAppModel {
    private var cursorCompanionController: CursorCompanionController?
    private var aiHotkeyController: AIHotkeyController?
    private let speechService = SpeechTranscriptionService()

    let aiService = AIIntegrationService()
    let imService = IMChannelService()
    let taskService = ScheduledTaskService()

    var isRecording = false
    var transcribedText = ""
    private var finalizedTranscript = ""
    private var volatileTranscript = ""
    private var currentScreenshotTask: Task<URL?, Never>?

    var menuBarTool: AIToolType? {
        aiService.preferredTool
    }

    var menuBarSessionLabel: String {
        if isRecording {
            return Self.liveTranscriptLabel(from: transcribedText)
        }

        if let statusLabel = aiService.deliveryState.menuLabel {
            return statusLabel
        }

        let trimmed = aiService.selectedSession.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "new session"
        }

        if trimmed == "new session" {
            return trimmed
        }

        return String(trimmed.prefix(5))
    }

    init() {
        taskService.aiService = aiService
        taskService.imService = imService
        imService.aiService = aiService

        activateCursorCompanion()
        activateAIHotkey()
        activateScheduledTasks()
    }

    func activateCursorCompanion() {
        if cursorCompanionController == nil {
            let controller = CursorCompanionController()
            controller.install()
            cursorCompanionController = controller
        }
    }

    func activateAIHotkey() {
        if aiHotkeyController == nil {
            let controller = AIHotkeyController()
            controller.install(
                onStart: { [weak self] in self?.startRecording() },
                onStop:  { [weak self] in self?.stopRecordingAndSend() }
            )
            aiHotkeyController = controller
        }
    }

    func activateScheduledTasks() {
        taskService.startAllTimers()
    }

    func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        transcribedText = ""
        finalizedTranscript = ""
        volatileTranscript = ""
        currentScreenshotTask?.cancel()
        currentScreenshotTask = Task {
            await Self.captureCurrentMouseScreen()
        }

        Task {
            do {
                let micGranted = await PermissionCoordinator.requestMicrophoneAccess()
                guard micGranted else {
                    isRecording = false
                    return
                }

                try await speechService.start(
                    locale: Locale(identifier: "zh-CN"),
                    onResult: { [weak self] segment in
                        guard let self else { return }
                        self.acceptSpeechSegment(segment)
                    },
                    onError: { [weak self] error in
                        self?.isRecording = false
                        self?.aiService.markFailed(error)
                        print("[Kara] Speech error: \(error)")
                    }
                )
            } catch {
                isRecording = false
                aiService.markFailed(error.localizedDescription)
                print("[Kara] Failed to start speech: \(error)")
            }
        }
    }

    func stopRecordingAndSend() {
        guard isRecording else { return }
        isRecording = false
        aiService.markTranscribing()

        Task {
            await speechService.stop()

            let text = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
            let screenshotURL = await currentScreenshotTask?.value
            guard let screenshotURL else {
                aiService.markFailed("需要授权屏幕截图后再发送")
                PermissionCoordinator.openScreenCaptureSettings()
                currentScreenshotTask = nil
                return
            }

            if !text.isEmpty {
                await aiService.deliverText(text, screenshotURL: screenshotURL)
                imService.broadcastMessage(text)
            } else {
                aiService.markFailed("没有识别到语音文本")
            }
            resetTranscriptState()
        }
    }

    private func resetTranscriptState() {
        transcribedText = ""
        finalizedTranscript = ""
        volatileTranscript = ""
        currentScreenshotTask = nil
    }

    private func acceptSpeechSegment(_ segment: SpeechSegment) {
        let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if segment.isFinal {
            finalizedTranscript = Self.joinTranscript(finalizedTranscript, text)
            volatileTranscript = ""
        } else {
            volatileTranscript = text
        }

        transcribedText = Self.joinTranscript(finalizedTranscript, volatileTranscript)
    }

    private static func joinTranscript(_ first: String, _ second: String) -> String {
        let parts = [first, second]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }

    private static func liveTranscriptLabel(from text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else {
            return "听写中"
        }

        return String(cleaned.suffix(9))
    }

    private static func captureCurrentMouseScreen() async -> URL? {
        if !PermissionCoordinator.hasScreenCaptureAccess(),
           !PermissionCoordinator.requestScreenCaptureAccess() {
            Self.log("screenshot unavailable: screen capture permission was not granted")
            return nil
        }

        guard let screen = Self.screenContainingMouse() ?? NSScreen.main,
              let displayID = Self.displayID(for: screen)
        else {
            return nil
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                return nil
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = display.width
            configuration.height = display.height
            configuration.showsCursor = true

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )

            let directory = try Self.screenshotDirectory()
            try Self.removeOldScreenshots(in: directory)

            let url = directory.appendingPathComponent("kara-screen-\(UUID().uuidString).png")

            return Self.writePNG(image, to: url) ? url : nil
        } catch {
            Self.log("screenshot capture failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return false
        }

        CGImageDestinationAddImage(destination, image, nil)
        let success = CGImageDestinationFinalize(destination)
        if success {
            Self.log("screenshot captured: \(url.path)")
        } else {
            Self.log("screenshot write failed: \(url.path)")
        }
        return success
    }

    private static func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }

    private static func screenshotDirectory() throws -> URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Kara/Screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func removeOldScreenshots(in directory: URL) throws {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        for url in urls where url.pathExtension.lowercased() == "png" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if let modified = values?.contentModificationDate, modified < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func log(_ message: String) {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Kara", isDirectory: true)
        let url = directory.appendingPathComponent("app.log")
        let line = "[\(Date())] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: url)
            }
        } catch {
            print("[Kara] \(message)")
        }
    }
}
