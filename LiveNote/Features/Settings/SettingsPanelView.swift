import SwiftUI
import CoreImage.CIFilterBuiltins

/// Unified settings panel with tabs: AI Tools, IM Channels, Scheduled Tasks.
struct SettingsPanelView: View {
    @Bindable var aiService: AIIntegrationService
    @Bindable var imService: IMChannelService
    @Bindable var taskService: ScheduledTaskService

    @State private var selectedTab: SettingsTab = .aiTools

    enum SettingsTab: String, CaseIterable {
        case aiTools    = "AI 工具"
        case imChannels = "IM 通道"
        case scheduled  = "定时任务"

        var icon: String {
            switch self {
            case .aiTools:    return "brain"
            case .imChannels: return "message"
            case .scheduled:  return "clock"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    tabButton(tab)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Tab content
            ScrollView {
                switch selectedTab {
                case .aiTools:
                    AIToolsSection(aiService: aiService)
                case .imChannels:
                    IMChannelsSection(imService: imService)
                case .scheduled:
                    ScheduledTasksSection(taskService: taskService, aiService: aiService, imService: imService)
                }
            }
        }
        .frame(width: 380, height: 480)
    }

    private func tabButton(_ tab: SettingsTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14))
                Text(tab.rawValue)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .foregroundStyle(selectedTab == tab ? Color.accentColor : .secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AI Tools Section

private struct AIToolsSection: View {
    @Bindable var aiService: AIIntegrationService
    @State private var testMessage: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerText("选择语音转写的目标 Agent")

            ForEach(AIToolType.allCases) { tool in
                AIToolRow(
                    tool: tool,
                    canSend: tool.canSendMessages,
                    isSelected: aiService.selectedTool == tool,
                    isExpanded: aiService.selectedTool == tool && tool.canSendMessages,
                    sessions: aiService.recentSessionsByTool[tool] ?? [],
                    isLoadingSessions: aiService.loadingRecentSessionTools.contains(tool),
                    selectedSessionID: aiService.selectedSession.externalID,
                    selectTool: {
                        guard tool.canSendMessages else { return }
                        aiService.selectedTool = (aiService.selectedTool == tool) ? nil : tool
                    },
                    clearSession: {
                        aiService.clearSelectedSession(for: tool)
                    },
                    selectSession: { session in
                        aiService.selectRecentSession(session)
                    }
                )
            }

            if aiService.installedTools.isEmpty {
                emptyAIState
            }

            testMessagePanel

            if let error = aiService.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
    }

    private var emptyAIState: some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.bubble")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("未检测到已安装的 AI 工具")
                .font(.caption.weight(.medium))
            Text("支持: Claude, Codex, Hermes CLI")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var testMessagePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("测试消息")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                        .foregroundStyle(.secondary)
                        .frame(width: 18)

                    TextField("输入测试内容", text: $testMessage, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.callout.weight(.medium))
                        .lineLimit(1...3)
                }

                HStack(spacing: 10) {
                    deliveryStatus
                    Spacer()
                    Button {
                        let message = testMessage
                        Task {
                            await aiService.deliverText(message)
                        }
                    } label: {
                        Label("发送", systemImage: "paperplane")
                    }
                    .controlSize(.small)
                    .disabled(
                        aiService.preferredTool == nil ||
                        !aiService.canSendToSelectedTool ||
                        testMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }

                if aiService.preferredTool != nil,
                   !aiService.canSendToSelectedTool {
                    Label("当前 Agent 未检测到可用安装", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                if let response = aiService.lastResponse,
                   !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("CLI 返回")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ScrollView {
                            Text(response)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 120)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.46))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.34), lineWidth: 1)
                    )
            )
        }
    }

    private var deliveryStatus: some View {
        Label(aiService.statusDetailText, systemImage: statusIconName)
            .font(.caption)
            .foregroundStyle(statusColor)
            .lineLimit(2)
    }

    private var statusIconName: String {
        switch aiService.deliveryState {
        case .idle:
            return "checkmark.circle"
        case .transcribing:
            return "waveform"
        case .sending:
            return "paperplane"
        case .delivered:
            return "checkmark.circle.fill"
        case .running:
            return "bolt.circle"
        case .completed:
            return "checkmark.seal.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch aiService.deliveryState {
        case .failed:
            return .orange
        case .delivered, .completed:
            return .green
        case .sending, .transcribing, .running:
            return .blue
        case .idle:
            return .secondary
        }
    }
}

private struct RecentSessionRow: View {
    let session: AgentRecentSession
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    if let icon = session.tool.brandIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .scaledToFit()
                            .padding(session.tool.baseTool == .codexCLI ? 0 : 2)
                    } else {
                        Image(systemName: session.tool.iconSystemName)
                            .font(.system(size: 14, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Text(session.displayTime)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if let projectName = session.projectName {
                            Text(projectName)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.primary.opacity(0.06))
                                )
                        }
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.66) : Color.white.opacity(0.38))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? Color.blue.opacity(0.42) : Color.white.opacity(0.26), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct RecentSessionSkeletonRow: View {
    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.primary.opacity(0.07))
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 6) {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 132, height: 9)

                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.055))
                    .frame(width: 84, height: 7)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.30))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
        )
        .redacted(reason: .placeholder)
    }
}

private struct NoSessionRow: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text("不指定 Session")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("发送到当前 Agent 默认窗口")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.66) : Color.white.opacity(0.38))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? Color.blue.opacity(0.42) : Color.white.opacity(0.26), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct AIToolRow: View {
    let tool: AIToolType
    let canSend: Bool
    let isSelected: Bool
    let isExpanded: Bool
    let sessions: [AgentRecentSession]
    let isLoadingSessions: Bool
    let selectedSessionID: String?
    let selectTool: () -> Void
    let clearSession: () -> Void
    let selectSession: (AgentRecentSession) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: selectTool) {
                HStack(spacing: 10) {
                    ZStack {
                        if let icon = tool.brandIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .scaledToFit()
                                .padding(tool.baseTool == .codexCLI ? 0 : 2)
                        } else {
                            Circle()
                                .fill(.white.opacity(isSelected ? 0.78 : 0.55))
                            Image(systemName: tool.iconSystemName)
                                .font(.system(size: 16, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                    .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(tool.displayName)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(canSend ? .primary : .tertiary)
                        HStack(spacing: 6) {
                            Text(tool.endpointDetail)
                                .font(.caption2)
                                .foregroundStyle(canSend ? .secondary : .tertiary)
                                .lineLimit(1)

                            if !canSend {
                                availabilityBadge(tool.unavailableSendReason)
                            }
                        }
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)

            if isExpanded {
                Divider()
                    .padding(.leading, 56)
                    .opacity(0.55)

                VStack(spacing: 4) {
                    NoSessionRow(isSelected: selectedSessionID == nil) {
                        clearSession()
                    }

                    if isLoadingSessions {
                        ForEach(0..<5, id: \.self) { _ in
                            RecentSessionSkeletonRow()
                        }
                    } else {
                        ForEach(sessions) { session in
                            RecentSessionRow(
                                session: session,
                                isSelected: selectedSessionID == session.externalID
                            ) {
                                selectSession(session)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(cardStroke, lineWidth: 1)
                )
        )
        .opacity(canSend ? 1 : 0.58)
    }

    private var cardFill: Color {
        if !canSend {
            return Color.white.opacity(0.24)
        }
        return isSelected ? Color.white.opacity(0.68) : Color.white.opacity(0.42)
    }

    private var cardStroke: Color {
        if !canSend {
            return Color.white.opacity(0.18)
        }
        return isSelected ? Color.blue.opacity(0.42) : Color.white.opacity(0.34)
    }

    private func availabilityBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(canSend ? .secondary : .tertiary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
    }
}

// MARK: - IM Channels Section

private struct IMChannelsSection: View {
    @Bindable var imService: IMChannelService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerText("配置 IM 通道，接收和转发消息")

            VStack(spacing: 10) {
                ForEach(IMPlatformType.visibleIMCases) { platform in
                    IMPlatformCard(platform: platform, imService: imService)
                }
            }

            if let error = imService.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .sheet(
            isPresented: Binding(
                get: { imService.wechatQRCodeURL != nil || imService.wechatStatus == .connecting || imService.wechatStatus == .waitingForScan },
                set: { isPresented in
                    if !isPresented {
                        imService.cancelWeChatLogin()
                    }
                }
            )
        ) {
            WeChatLoginSheet(imService: imService)
        }
    }
}

private struct IMPlatformCard: View {
    let platform: IMPlatformType
    @Bindable var imService: IMChannelService

    var body: some View {
        HStack(spacing: 10) {
            platformIcon

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 7) {
                    Text(platform.displayName)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(isAvailable ? .primary : .secondary)

                    if platform == .wechat, imService.isWeChatConnected {
                        Text("已连接")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.green.opacity(0.12))
                            )
                    }

                    if platform == .wechat, imService.isWeChatConnected {
                        Text(imService.wechatAgentState.label)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(agentStateColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(agentStateColor.opacity(0.12))
                            )
                    }
                }

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                if platform == .wechat {
                    if imService.isWeChatConnected {
                        imService.disconnectWeChat()
                    } else {
                        imService.startWeChatLogin()
                    }
                }
            } label: {
                Text(actionTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isAvailable ? .white : .secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isAvailable ? Color.primary.opacity(0.88) : Color.primary.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isAvailable)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isAvailable ? Color.white.opacity(0.42) : Color.white.opacity(0.22))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(isAvailable ? 0.34 : 0.18), lineWidth: 1)
                )
        )
        .opacity(isAvailable ? 1 : 0.58)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var platformIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(iconBackground)

            Image(systemName: platform.iconSystemName)
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor)
        }
        .frame(width: 34, height: 34)
    }

    private var isAvailable: Bool {
        platform == .wechat
    }

    private var subtitle: String {
        switch platform {
        case .wechat:
            switch imService.wechatStatus {
            case .connected(let accountID):
                let detail = imService.wechatAgentState.detail
                    .map { " · \($0)" } ?? ""
                return "通过微信机器人接收并回复用户消息 · \(accountID)\(detail)"
            case .connecting:
                return "正在生成微信扫码登录二维码"
            case .waitingForScan:
                return "请使用手机微信扫码完成连接"
            case .failed(let message):
                return message
            case .disconnected:
                return "通过微信机器人接收并回复用户消息"
            }
        case .feishu:
            return "飞书通道稍后支持"
        default:
            return ""
        }
    }

    private var actionTitle: String {
        switch platform {
        case .wechat:
            return imService.isWeChatConnected ? "断开" : "配置"
        case .feishu:
            return "稍后"
        default:
            return "不可用"
        }
    }

    private var iconBackground: Color {
        switch platform {
        case .wechat:
            return Color.green.opacity(0.12)
        case .feishu:
            return Color.blue.opacity(0.08)
        default:
            return Color.primary.opacity(0.06)
        }
    }

    private var iconColor: Color {
        switch platform {
        case .wechat:
            return .green
        case .feishu:
            return .blue
        default:
            return .secondary
        }
    }

    private var agentStateColor: Color {
        switch imService.wechatAgentState {
        case .idle:
            return .secondary
        case .listening:
            return .blue
        case .running:
            return .orange
        case .replied:
            return .green
        case .failed:
            return .red
        }
    }
}

private struct WeChatLoginSheet: View {
    @Bindable var imService: IMChannelService
    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.14))
                            .frame(width: 54, height: 54)
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 23, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                    .offset(y: -10)

                    Text("扫码登录")
                        .font(.title3.weight(.semibold))

                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    qrContent
                        .frame(width: 210, height: 210)
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 28)

                Button {
                    imService.cancelWeChatLogin()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.82))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(12)
            }

            Divider()

            Button {
                imService.startWeChatLogin()
            } label: {
                Text("重新生成")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.88))
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 318)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var qrContent: some View {
        if let image = qrImage {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
                )
        } else {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var qrImage: NSImage? {
        guard let qrURL = imService.wechatQRCodeURL else {
            return nil
        }
        let data = Data(qrURL.absoluteString.utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else {
            return nil
        }

        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: 210, height: 210))
    }

    private var statusText: String {
        switch imService.wechatStatus {
        case .connecting:
            return "正在生成二维码..."
        case .waitingForScan:
            return "请使用微信扫描下方二维码完成连接"
        case .connected:
            return "微信已连接"
        case .failed(let message):
            return message
        case .disconnected:
            return "请使用微信扫描下方二维码完成连接"
        }
    }
}

// MARK: - Scheduled Tasks Section

private struct ScheduledTasksSection: View {
    @Bindable var taskService: ScheduledTaskService
    let aiService: AIIntegrationService
    let imService: IMChannelService
    @State private var showingAddSheet = false
    @State private var editingTask: ScheduledTask?
    @State private var selectedList: ScheduledTaskList = .tasks
    @State private var sortDescending = true

    private enum ScheduledTaskList: String, CaseIterable, Identifiable {
        case tasks = "我的定时任务"
        case runs = "执行记录"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            pageHeader
            wakeNotice
            listHeader

            switch selectedList {
            case .tasks:
                taskList
            case .runs:
                runList
            }
        }
        .padding(16)
        .sheet(isPresented: $showingAddSheet) {
            TaskEditorSheet(taskService: taskService, aiService: aiService, imService: imService)
        }
        .sheet(item: $editingTask) { task in
            TaskEditorSheet(taskService: taskService, aiService: aiService, imService: imService, task: task)
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("定时任务")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.primary)

                    Text("按计划自动执行任务，也可随时手动触发。")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.92))
                        )
                }
                .buttonStyle(.plain)
            }

            Button {
                aiService.refreshRecentSessions()
            } label: {
                Label("刷新最近会话", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var wakeNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.blue)

            Text("定时任务仅在电脑保持唤醒时运行")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.blue)
                .lineLimit(1)

            Spacer()

            Toggle("保持唤醒", isOn: Binding(
                get: { taskService.keepSystemAwake },
                set: { taskService.setKeepSystemAwake($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.blue)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.88, green: 0.96, blue: 1.0))
        )
    }

    private var listHeader: some View {
        HStack(alignment: .center, spacing: 18) {
            ForEach(ScheduledTaskList.allCases) { item in
                Button {
                    selectedList = item
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 16, weight: selectedList == item ? .bold : .semibold))
                        .foregroundStyle(selectedList == item ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if selectedList == .tasks {
                Button {
                    sortDescending.toggle()
                } label: {
                    Label(sortDescending ? "按创建时间倒序" : "按创建时间正序", systemImage: "line.3.horizontal.decrease")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .labelStyle(.iconOnly)
                        .frame(width: 32, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .windowBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sortedTasks: [ScheduledTask] {
        taskService.tasks.sorted {
            sortDescending ? $0.createdAt > $1.createdAt : $0.createdAt < $1.createdAt
        }
    }

    @ViewBuilder
    private var taskList: some View {
        if taskService.tasks.isEmpty {
            VStack(spacing: 7) {
                Image(systemName: "clock.badge.questionmark")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("暂未配置定时任务")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        } else {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 0)
                ],
                spacing: 10
            ) {
                ForEach(sortedTasks) { task in
                    ScheduledTaskRow(
                        task: task,
                        taskService: taskService,
                        edit: { editingTask = task }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var runList: some View {
        if taskService.runs.isEmpty {
            VStack(spacing: 7) {
                Image(systemName: "list.bullet.clipboard")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("还没有执行记录")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        } else {
            VStack(spacing: 8) {
                ForEach(taskService.runs) { run in
                    ScheduledTaskRunRow(run: run)
                }
            }
        }
    }
}

private struct ScheduledTaskRow: View {
    let task: ScheduledTask
    @Bindable var taskService: ScheduledTaskService
    let edit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 10) {
                Toggle("", isOn: Binding(
                    get: { task.isEnabled },
                    set: { _ in taskService.toggleTask(id: task.id) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()

                Spacer()

                Menu {
                    Button {
                        taskService.runNow(id: task.id)
                    } label: {
                        Label("立即执行", systemImage: "play")
                    }

                    Button {
                        edit()
                    } label: {
                        Label("编辑任务", systemImage: "square.and.pencil")
                    }

                    Divider()

                    Button(role: .destructive) {
                        taskService.removeTask(id: task.id)
                    } label: {
                        Label("删除任务", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 24)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            VStack(alignment: .leading, spacing: 9) {
                Text(task.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(task.prompt)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Rectangle()
                .fill(Color.clear)
                .frame(height: 1)
                .overlay(
                    Rectangle()
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 6]))
                        .foregroundStyle(Color.primary.opacity(0.12))
                )

            HStack(spacing: 8) {
                Label(task.scheduleText, systemImage: "clock")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.72))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(red: 0.96, green: 0.94, blue: 0.91))
                    )

                Spacer()

                if let lastRun = task.lastRunAt {
                    Text(lastRun.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .frame(minHeight: 126, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.025), radius: 12, x: 0, y: 6)
    }
}

private struct ScheduledTaskRunRow: View {
    let run: ScheduledTaskRun

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: run.status == .succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(run.status == .succeeded ? .green : .orange)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(run.taskName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(run.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(run.ranAt.formatted(.dateTime.month().day().hour().minute()))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.36))
        )
    }
}

private struct TaskEditorSheet: View {
    @Bindable var taskService: ScheduledTaskService
    let aiService: AIIntegrationService
    let imService: IMChannelService
    let task: ScheduledTask?
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var prompt = ""
    @State private var cadence: ScheduledTaskCadence = .daily
    @State private var hour = 9
    @State private var minute = 30
    @State private var targetTool: AIToolType?
    @State private var targetChannelID: UUID?

    init(
        taskService: ScheduledTaskService,
        aiService: AIIntegrationService,
        imService: IMChannelService,
        task: ScheduledTask? = nil
    ) {
        self.taskService = taskService
        self.aiService = aiService
        self.imService = imService
        self.task = task
        _name = State(initialValue: task?.name ?? "")
        _prompt = State(initialValue: task?.prompt ?? "")
        _cadence = State(initialValue: task?.cadence ?? .daily)
        _hour = State(initialValue: task?.hour ?? 9)
        _minute = State(initialValue: task?.minute ?? 30)
        _targetTool = State(initialValue: task?.targetTool ?? aiService.preferredTool)
        _targetChannelID = State(initialValue: task?.targetChannelID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            sheetHeader

            fieldBlock("任务名称") {
                TextField("例如：每日数据报表更新", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(inputBackground)
            }

            fieldBlock("计划时间") {
                HStack(spacing: 9) {
                    compactPicker(width: 96) {
                        Picker("", selection: $cadence) {
                            ForEach(ScheduledTaskCadence.allCases) { item in
                                Text(item.displayName).tag(item)
                            }
                        }
                    }

                    compactPicker(width: 72) {
                        Picker("", selection: $hour) {
                            ForEach(0..<24, id: \.self) { value in
                                Text(String(format: "%02d", value)).tag(value)
                            }
                        }
                    }

                    Text(":")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary.opacity(0.65))

                    compactPicker(width: 72) {
                        Picker("", selection: $minute) {
                            ForEach(stride(from: 0, through: 55, by: 5).map { $0 }, id: \.self) { value in
                                Text(String(format: "%02d", value)).tag(value)
                            }
                        }
                    }
                }
            }

            fieldBlock("让 Agent 帮你做什么...") {
                VStack(spacing: 0) {
                    TextEditor(text: $prompt)
                        .font(.system(size: 14))
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .frame(minHeight: 170)

                    HStack(spacing: 8) {
                        if !imService.channels.isEmpty {
                            compactPicker(width: 106) {
                                Picker("", selection: $targetChannelID) {
                                    Text("不转发").tag(nil as UUID?)
                                    ForEach(imService.channels) { channel in
                                        Text("\(channel.platform.displayName) - \(channel.name)").tag(channel.id as UUID?)
                                    }
                                }
                            }
                        }

                        Spacer()

                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)

                        compactPicker(width: 98) {
                            Picker("", selection: $targetTool) {
                                Text("Auto").tag(nil as AIToolType?)
                                ForEach(AIToolType.allCases) { tool in
                                    Text(tool.compactDisplayName).tag(tool as AIToolType?)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
                .background(inputBackground)
            }

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("取消")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.72))
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                }
                .buttonStyle(.plain)

                Button {
                    save()
                    dismiss()
                } label: {
                    Text("保存")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 34)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.primary.opacity(0.92))
                        )
                }
                .buttonStyle(.plain)
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .frame(width: 420)
    }

    private var sheetHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(task == nil ? "新建任务" : "编辑任务")
                    .font(.system(size: 19, weight: .bold))
                Text("按计划自动执行，也可随时手动触发。")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.78))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
        }
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(nsColor: .textBackgroundColor).opacity(0.96))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )
    }

    private func fieldBlock<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary.opacity(0.82))
            content()
        }
    }

    private func compactPicker<Content: View>(width: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        content()
            .labelsHidden()
            .pickerStyle(.menu)
            .font(.system(size: 13, weight: .semibold))
            .frame(width: width, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.primary.opacity(0.055), lineWidth: 1)
            )
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        if var task {
            task.name = trimmedName.isEmpty ? "定时任务" : trimmedName
            task.prompt = trimmedPrompt
            task.cadence = cadence
            task.hour = hour
            task.minute = minute
            task.targetTool = targetTool
            task.targetChannelID = targetChannelID
            taskService.updateTask(task)
        } else {
            taskService.addTask(
                ScheduledTask(
                    name: trimmedName.isEmpty ? "定时任务" : trimmedName,
                    prompt: trimmedPrompt,
                    cadence: cadence,
                    hour: hour,
                    minute: minute,
                    targetTool: targetTool,
                    targetChannelID: targetChannelID
                )
            )
        }
    }
}

// MARK: - Shared helpers

private func headerText(_ text: String) -> some View {
    Text(text)
        .font(.caption)
        .foregroundStyle(.secondary)
}

private func sectionLabel(_ text: String) -> some View {
    Text(text)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.tertiary)
        .textCase(.uppercase)
        .padding(.top, 4)
}
