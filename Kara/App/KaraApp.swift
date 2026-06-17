import SwiftUI
import Observation
import AppKit
import ImageIO
import ScreenCaptureKit
import Speech
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
        popover.contentSize = NSSize(width: 520, height: 700)
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
    @State private var showingSettings = false
    @State private var isEditingRequest = false
    @State private var draftText = ""

    var body: some View {
        Group {
            if showingSettings {
                settingsPanel
            } else {
                runtimePanel
            }
        }
        .frame(width: 520, height: 700)
        .background(.regularMaterial)
    }

    private var runtimePanel: some View {
        VStack(spacing: 0) {
            runtimeHeader

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    retainedInputSection
                    errorSection
                    bridgeSection
                    permissionSection
                    actionGrid
                    editSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }

            Divider()

            footer
        }
    }

    private var settingsPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    showingSettings = false
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)

                Text("设置")
                    .font(.headline)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            SettingsPanelView(
                aiService: appModel.aiService,
                imService: appModel.imService,
                taskService: appModel.taskService
            )
        }
    }

    private var runtimeHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(headerTint.opacity(0.16))
                Image(systemName: headerIcon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(headerTint)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(headerTitle)
                    .font(.system(size: 22, weight: .semibold))
                Text(headerSubtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private var retainedInputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("保留的输入")

            VStack(spacing: 0) {
                transcriptRow
                Divider()
                    .padding(.leading, 70)
                screenshotRow
            }
            .background(panelCardBackground)
        }
    }

    private var transcriptRow: some View {
        HStack(alignment: .top, spacing: 14) {
            CircleIcon(systemName: "bubble.left", tint: .blue)

            VStack(alignment: .leading, spacing: 7) {
                Text("转写文本")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(displayTranscript)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(displayedRequest == nil && !appModel.isRecording ? .secondary : .primary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
    }

    private var screenshotRow: some View {
        HStack(alignment: .top, spacing: 14) {
            CircleIcon(systemName: "photo", tint: .green)

            VStack(alignment: .leading, spacing: 7) {
                Text("截图")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(screenshotStatusText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(screenshotURL == nil ? Color.secondary : Color.green)

                if let metadata = screenshotMetadata {
                    Text(metadata)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 10)

            ScreenshotPreview(url: screenshotURL)
                .frame(width: 190, height: 118)
        }
        .padding(16)
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorText {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("错误原因")

                HStack(spacing: 14) {
                    CircleIcon(systemName: "xmark", tint: .red)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(errorSummary(errorText))
                            .font(.system(size: 17, weight: .semibold))
                            .lineLimit(2)
                        Text(errorDetail(errorText))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
                .background(panelCardBackground)
            }
        }
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("权限状态")

            VStack(spacing: 0) {
                PermissionStatusRow(
                    icon: "mic",
                    title: "麦克风",
                    isGranted: PermissionCoordinator.microphoneStatus == .granted
                )
                Divider()
                    .padding(.leading, 52)
                PermissionStatusRow(
                    icon: "waveform",
                    title: "语音识别",
                    isGranted: SFSpeechRecognizer.authorizationStatus() == .authorized
                )
                Divider()
                    .padding(.leading, 52)
                PermissionStatusRow(
                    icon: "display",
                    title: "屏幕录制",
                    isGranted: PermissionCoordinator.hasScreenCaptureAccess()
                )
            }
            .background(panelCardBackground)
        }
    }

    private var bridgeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Agent Bridge")

            HStack(spacing: 14) {
                CircleIcon(systemName: "point.3.connected.trianglepath.dotted", tint: bridgeTint)

                VStack(alignment: .leading, spacing: 5) {
                    Text(bridgeStateText)
                        .font(.system(size: 16, weight: .semibold))
                    Text(bridgeDetailText)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Text("#\(appModel.aiService.bridgeService.lastSeq)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(panelCardBackground)
        }
    }

    private var actionGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    Task { await appModel.aiService.retryLastRequest() }
                } label: {
                    Label("重发", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(displayedRequest == nil)

                Button {
                    showingSettings = true
                } label: {
                    Label("换 Agent 发送", systemImage: "arrow.left.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }

            HStack(spacing: 10) {
                Button {
                    beginEditingRequest()
                } label: {
                    Label(isEditingRequest ? "收起编辑" : "编辑后发送", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(displayedRequest == nil)

                Button {
                    copyError()
                } label: {
                    Label("复制错误", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(errorText == nil)
            }
        }
    }

    @ViewBuilder
    private var editSection: some View {
        if isEditingRequest {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("编辑后发送")

                VStack(alignment: .leading, spacing: 12) {
                    TextEditor(text: $draftText)
                        .font(.system(size: 15))
                        .frame(height: 110)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .textBackgroundColor).opacity(0.82))
                        )

                    HStack(spacing: 10) {
                        Button {
                            isEditingRequest = false
                        } label: {
                            Text("取消")
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)

                        Button {
                            Task { await sendEditedRequest() }
                        } label: {
                            Label("发送", systemImage: "paperplane")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(16)
                .background(panelCardBackground)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 18) {
            Button("查看日志") {
                openLogs()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)

            Text("|")
                .foregroundStyle(.tertiary)

            Button("打开设置") {
                showingSettings = true
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button("退出 Kara") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .font(.system(size: 14))
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .semibold))
    }

    private var panelCardBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.82))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.09), lineWidth: 1)
            )
    }

    private var headerTitle: String {
        if case .failed = appModel.aiService.deliveryState {
            return "需要处理"
        }
        if appModel.isRecording {
            return "正在听"
        }
        return appModel.menuBarTool?.compactDisplayName ?? "Kara"
    }

    private var headerSubtitle: String {
        if case .failed = appModel.aiService.deliveryState {
            return "请求未发送成功"
        }
        if appModel.isRecording {
            return "松开 Option 后发送"
        }
        return "语音会发送给当前 Agent"
    }

    private var bridgeStateText: String {
        switch appModel.aiService.bridgeService.state {
        case .initializing:
            return "Bridge 初始化中"
        case .waiting:
            return "Bridge 已连接"
        case .running:
            return "Agent 正在执行"
        case .draining:
            return "正在停止当前请求"
        case .done:
            return "Bridge 已断开"
        }
    }

    private var bridgeDetailText: String {
        if let reason = appModel.aiService.bridgeService.lastRouteReason {
            return reason
        }
        return "Kara 会通过常驻 Bridge 路由到合适的 Agent/session"
    }

    private var bridgeTint: Color {
        switch appModel.aiService.bridgeService.state {
        case .initializing:
            return .orange
        case .waiting:
            return .green
        case .running:
            return .blue
        case .draining:
            return .orange
        case .done:
            return .secondary
        }
    }

    private var headerIcon: String {
        if case .failed = appModel.aiService.deliveryState {
            return "exclamationmark"
        }
        return appModel.isRecording ? "mic.fill" : "waveform"
    }

    private var headerTint: Color {
        if case .failed = appModel.aiService.deliveryState {
            return .red
        }
        return appModel.isRecording ? .red : .blue
    }

    private var activeRequest: AgentDeliveryRequest? {
        switch appModel.aiService.deliveryState {
        case .sending(let request), .delivered(let request), .running(let request), .completed(let request):
            return request
        default:
            return nil
        }
    }

    private var displayedRequest: AgentDeliveryRequest? {
        appModel.aiService.lastFailedRequest ?? activeRequest ?? appModel.aiService.lastRequest
    }

    private var displayTranscript: String {
        let liveText = appModel.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !liveText.isEmpty {
            return liveText
        }
        return displayedRequest?.text ?? "按住 Option 说话后会显示转写文本"
    }

    private var screenshotURL: URL? {
        displayedRequest?.screenshotURL
    }

    private var screenshotStatusText: String {
        screenshotURL == nil ? "等待截图" : "已捕获"
    }

    private var screenshotMetadata: String? {
        guard let url = screenshotURL else { return nil }
        let size = Self.imagePixelSize(url: url)
        let time = Self.fileModificationTime(url: url)

        switch (size, time) {
        case (.some(let size), .some(let time)):
            return "\(Int(size.width)) x \(Int(size.height)) · \(time)"
        case (.some(let size), .none):
            return "\(Int(size.width)) x \(Int(size.height))"
        case (.none, .some(let time)):
            return time
        case (.none, .none):
            return nil
        }
    }

    private var errorText: String? {
        if case .failed(let message) = appModel.aiService.deliveryState {
            return message
        }
        return appModel.aiService.lastFailedRequest == nil ? nil : appModel.aiService.lastError
    }

    private func errorSummary(_ error: String) -> String {
        let firstLine = error
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? error
        if firstLine.contains("No prompt provided") {
            return "Codex CLI 没有收到 prompt"
        }
        if firstLine.count > 34 {
            return String(firstLine.prefix(34)) + "..."
        }
        return firstLine
    }

    private func errorDetail(_ error: String) -> String {
        if error.contains("No prompt provided") {
            return "已改用 stdin 传递文本后可重试"
        }
        return "语音文本和截图已保留，可重发"
    }

    private func beginEditingRequest() {
        if isEditingRequest {
            isEditingRequest = false
            return
        }
        draftText = displayedRequest?.text ?? displayTranscript
        isEditingRequest = true
    }

    private func sendEditedRequest() async {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isEditingRequest = false
        await appModel.aiService.deliverText(text, screenshotURL: screenshotURL)
    }

    private func copyError() {
        guard let errorText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(errorText, forType: .string)
    }

    private func openLogs() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Kara", isDirectory: true)
        NSWorkspace.shared.open(url)
    }

    private static func imagePixelSize(url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else {
            return nil
        }
        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }

    private static func fileModificationTime(url: URL) -> String? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        guard let date = values?.contentModificationDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

private struct CircleIcon: View {
    let systemName: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.14))
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 42, height: 42)
    }
}

private struct ScreenshotPreview: View {
    let url: URL?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 190, height: 118)
                    .clipped()
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "display")
                        .font(.system(size: 22))
                    Text("暂无预览")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private var image: NSImage? {
        guard let url else { return nil }
        return NSImage(contentsOf: url)
    }
}

private struct PermissionStatusRow: View {
    let icon: String
    let title: String
    let isGranted: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.primary.opacity(0.06))
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                )

            Text(title)
                .font(.system(size: 15, weight: .medium))

            Spacer()

            Text(isGranted ? "已授权" : "未授权")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isGranted ? .green : .orange)

            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isGranted ? .green : .orange)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
