import Foundation
import AppKit
import Observation
import WChatClawSwift

/// A configured IM channel that can send/receive messages.
struct IMChannel: Identifiable, Codable, Hashable {
    let id: UUID
    var platform: IMPlatformType
    var name: String          // User-given label, e.g. "研发团队"
    var webhookURL: String
    var isEnabled: Bool

    init(id: UUID = UUID(), platform: IMPlatformType, name: String, webhookURL: String, isEnabled: Bool = true) {
        self.id = id
        self.platform = platform
        self.name = name
        self.webhookURL = webhookURL
        self.isEnabled = isEnabled
    }
}

/// Manages IM channel configurations and message forwarding.
@MainActor
@Observable
final class IMChannelService {
    var channels: [IMChannel] = []
    var lastError: String?
    var wechatQRCodeURL: URL?
    var wechatStatus: WeChatConnectionStatus = .disconnected
    var wechatAgentState: WeChatAgentState = .idle
    var wechatAccountID: String?
    weak var aiService: AIIntegrationService? {
        didSet {
            startWeChatAgentIfPossible()
        }
    }

    private let storageKey = "LiveNote.imChannels"
    private let wechatUpdatesBufferKey = "LiveNote.wechatUpdatesBuffer"
    private let wechatLoginManager = QRLoginManager()
    private let wechatAccountStore = AccountStore()
    private var wechatLoginTask: Task<Void, Never>?
    private var wechatAgentTask: Task<Void, Never>?
    private var wechatAgentBootstrapTask: Task<Void, Never>?

    init() {
        loadChannels()
        loadWeChatConnectionState()
        startWeChatAgentBootstrap()
    }

    // MARK: - CRUD

    func addChannel(_ channel: IMChannel) {
        channels.append(channel)
        save()
    }

    func updateChannel(_ channel: IMChannel) {
        if let idx = channels.firstIndex(where: { $0.id == channel.id }) {
            channels[idx] = channel
            save()
        }
    }

    func removeChannel(id: UUID) {
        channels.removeAll { $0.id == id }
        save()
    }

    func toggleChannel(id: UUID) {
        if let idx = channels.firstIndex(where: { $0.id == id }) {
            channels[idx].isEnabled.toggle()
            save()
        }
    }

    // MARK: - WeChat iLink

    var isWeChatConnected: Bool {
        if case .connected = wechatStatus {
            return true
        }
        return false
    }

    func startWeChatLogin() {
        wechatLoginTask?.cancel()
        lastError = nil
        wechatQRCodeURL = nil
        wechatStatus = .connecting

        wechatLoginTask = Task { [weak self] in
            do {
                guard let self else { return }
                let login = try await self.wechatLoginManager.start()

                await MainActor.run {
                    self.wechatQRCodeURL = login.qrcodeURL
                    self.wechatStatus = .waitingForScan
                }

                let result = try await self.wechatLoginManager.wait()
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    if let account = result.account {
                        self.wechatAccountID = account.accountID
                        self.wechatStatus = .connected(account.accountID)
                        self.startWeChatAgentIfPossible()
                    } else if result.alreadyConnected {
                        self.loadWeChatConnectionState()
                        self.wechatStatus = .connected(self.wechatAccountID ?? "微信")
                        self.startWeChatAgentIfPossible()
                    } else {
                        self.wechatStatus = .failed(result.message)
                        self.lastError = result.message
                    }
                    self.wechatQRCodeURL = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.wechatQRCodeURL = nil
                    self?.wechatStatus = .failed(error.localizedDescription)
                    self?.lastError = error.localizedDescription
                }
            }
        }
    }

    func cancelWeChatLogin() {
        wechatLoginTask?.cancel()
        wechatLoginTask = nil
        Task {
            await wechatLoginManager.cancel()
        }
        wechatQRCodeURL = nil
        if !isWeChatConnected {
            wechatStatus = .disconnected
        }
    }

    func disconnectWeChat() {
        cancelWeChatLogin()
        stopWeChatAgent()
        try? wechatAccountStore.removeAll()
        UserDefaults.standard.removeObject(forKey: wechatUpdatesBufferKey)
        wechatAccountID = nil
        wechatStatus = .disconnected
        wechatAgentState = .idle
        lastError = nil
    }

    func startWeChatAgentIfPossible() {
        guard wechatAgentTask == nil else {
            return
        }
        guard let account = try? wechatAccountStore.latest() else {
            Self.log("wechat agent start skipped: no local account")
            return
        }
        guard let aiService else {
            Self.log("wechat agent start skipped: ai service not ready")
            return
        }

        wechatAccountID = account.accountID
        wechatStatus = .connected(account.accountID)

        let updatesBufferKey = wechatUpdatesBufferKey
        let reporter = WeChatAgentEventReporter(service: self)
        Self.log("starting wechat agent for account \(account.accountID)")
        wechatAgentTask = Task { [aiService, reporter] in
            defer {
                Self.log("wechat agent task ended")
                Task { await reporter.clearRunningTask() }
            }

            let client = ILinkClient()
            let bridge = WeixinAgentBridge(account: account, client: client)
            var updatesBuffer = UserDefaults.standard.string(forKey: updatesBufferKey) ?? ""
            var emptyPollCount = 0

            Task {
                await reporter.setState(.listening)
            }
            Self.log("wechat agent listening; saved buffer is \(updatesBuffer.isEmpty ? "empty" : "present")")

            while !Task.isCancelled {
                do {
                    let replyCount = try await bridge.processNextBatch(updatesBuffer: &updatesBuffer) { incoming in
                        let incomingText = incoming.text
                        Self.log("received message from \(incoming.senderID ?? "unknown"): \(Self.previewText(incomingText))")
                        Task {
                            await reporter.setState(.running(Self.previewText(incomingText)))
                        }

                        if let senderID = incoming.senderID {
                            do {
                                try await client.sendText(
                                    "思考中...",
                                    to: senderID,
                                    account: incoming.account,
                                    contextToken: incoming.contextToken
                                )
                                Self.log("sent thinking message to \(senderID)")
                            } catch {
                                Self.log("failed to send thinking message: \(error.localizedDescription)")
                            }
                        }

                        let progressTask: Task<Void, Never>? = incoming.senderID.map { senderID in
                            Task {
                                try? await Task.sleep(for: .seconds(20))
                                while !Task.isCancelled {
                                    do {
                                        try await client.sendText(
                                            "还在处理...",
                                            to: senderID,
                                            account: incoming.account,
                                            contextToken: incoming.contextToken
                                        )
                                        Self.log("sent progress message to \(senderID)")
                                    } catch {
                                        Self.log("failed to send progress message: \(error.localizedDescription)")
                                    }
                                    try? await Task.sleep(for: .seconds(30))
                                }
                            }
                        }
                        defer {
                            progressTask?.cancel()
                        }

                        do {
                            let reply = try await aiService.deliverTextForReply(incomingText)
                            Task {
                                await reporter.setState(.replied(Self.previewText(incomingText)))
                            }
                            Self.log("agent completed reply for: \(Self.previewText(incomingText))")
                            return reply
                        } catch {
                            let message = error.localizedDescription
                            Task {
                                await reporter.setState(.failed(message), error: message)
                            }
                            Self.log("agent failed: \(message)")
                            return "执行失败：\(message)"
                        }
                    }

                    UserDefaults.standard.set(updatesBuffer, forKey: updatesBufferKey)
                    if replyCount > 0 {
                        emptyPollCount = 0
                        Self.log("processed \(replyCount) wechat message(s)")
                    }
                    if replyCount == 0 {
                        emptyPollCount += 1
                        if emptyPollCount == 1 || emptyPollCount % 3 == 0 {
                            Self.log("wechat poll returned no messages (\(emptyPollCount) empty poll(s))")
                        }
                        Task {
                            await reporter.setListeningUnlessFailed()
                        }
                    }
                } catch is CancellationError {
                    break
                } catch {
                    Self.log("poll failed: \(error.localizedDescription)")
                    Task {
                        await reporter.setState(
                            .failed(error.localizedDescription),
                            error: "微信监听失败: \(error.localizedDescription)"
                        )
                    }
                    try? await Task.sleep(for: .seconds(3))
                }
            }
        }
    }

    func stopWeChatAgent() {
        wechatAgentTask?.cancel()
        wechatAgentTask = nil
        if isWeChatConnected {
            wechatAgentState = .idle
        }
    }

    fileprivate func clearWeChatAgentTask() {
        wechatAgentTask = nil
    }

    private func startWeChatAgentBootstrap() {
        guard wechatAgentBootstrapTask == nil else { return }
        wechatAgentBootstrapTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run {
                    self?.loadWeChatConnectionState()
                    self?.startWeChatAgentIfPossible()
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    // MARK: - Send message to IM channel

    func sendMessage(_ text: String, to channelID: UUID) {
        guard let channel = channels.first(where: { $0.id == channelID }),
              channel.isEnabled else {
            lastError = "通道不可用"
            return
        }

        guard let url = URL(string: channel.webhookURL), !channel.webhookURL.isEmpty else {
            lastError = "Webhook URL 无效"
            return
        }

        lastError = nil

        let body = buildRequestBody(for: channel.platform, text: text)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        Task {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    lastError = "发送失败 (HTTP \(httpResponse.statusCode))"
                }
            } catch {
                lastError = "发送失败: \(error.localizedDescription)"
            }
        }
    }

    /// Broadcast text to all enabled channels.
    func broadcastMessage(_ text: String) {
        for channel in channels where channel.isEnabled {
            sendMessage(text, to: channel.id)
        }
    }

    // MARK: - Platform-specific request bodies

    private func buildRequestBody(for platform: IMPlatformType, text: String) -> Data? {
        let dict: [String: Any]
        switch platform {
        case .wechat:
            dict = ["text": text]
        case .dingtalk:
            dict = [
                "msgtype": "text",
                "text": ["content": text]
            ]
        case .feishu:
            dict = [
                "msg_type": "text",
                "content": ["text": text]
            ]
        case .wecom:
            dict = [
                "msgtype": "text",
                "text": ["content": text]
            ]
        case .slack:
            dict = ["text": text]
        case .telegram:
            // Telegram uses Bot API URL, not webhook
            dict = ["text": text]
        }
        return try? JSONSerialization.data(withJSONObject: dict)
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(channels) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadChannels() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([IMChannel].self, from: data) else { return }
        channels = decoded
    }

    private func loadWeChatConnectionState() {
        if let account = try? wechatAccountStore.latest() {
            wechatAccountID = account.accountID
            wechatStatus = .connected(account.accountID)
            startWeChatAgentIfPossible()
        } else {
            wechatAccountID = nil
            wechatStatus = .disconnected
            wechatAgentState = .idle
        }
    }

    nonisolated private static func previewText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 18 else { return trimmed }
        return String(trimmed.prefix(18)) + "..."
    }

    nonisolated private static func log(_ message: String) {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/LiveNote", isDirectory: true)
        let url = directory.appendingPathComponent("wechat-agent.log")
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
            print("[LiveNote] \(message)")
        }
    }
}

enum WeChatConnectionStatus: Equatable {
    case disconnected
    case connecting
    case waitingForScan
    case connected(String)
    case failed(String)

    var label: String {
        switch self {
        case .disconnected:
            return "未连接"
        case .connecting:
            return "生成中"
        case .waitingForScan:
            return "等待扫码"
        case .connected:
            return "已连接"
        case .failed:
            return "连接失败"
        }
    }
}

private actor WeChatAgentEventReporter {
    private weak var service: IMChannelService?

    init(service: IMChannelService) {
        self.service = service
    }

    func setState(_ state: WeChatAgentState, error: String? = nil) async {
        let service = service
        await MainActor.run {
            service?.wechatAgentState = state
            if let error {
                service?.lastError = error
            }
        }
    }

    func setListeningUnlessFailed() async {
        let service = service
        await MainActor.run {
            guard let service else { return }
            if case .failed = service.wechatAgentState {
                return
            }
            service.wechatAgentState = .listening
        }
    }

    func clearRunningTask() async {
        let service = service
        await MainActor.run {
            service?.clearWeChatAgentTask()
        }
    }
}

enum WeChatAgentState: Equatable {
    case idle
    case listening
    case running(String)
    case replied(String)
    case failed(String)

    var label: String {
        switch self {
        case .idle:
            return "未监听"
        case .listening:
            return "监听中"
        case .running:
            return "执行中"
        case .replied:
            return "已回复"
        case .failed:
            return "监听异常"
        }
    }

    var detail: String? {
        switch self {
        case .idle, .listening:
            return nil
        case .running(let text):
            return "正在处理：\(text)"
        case .replied(let text):
            return "已回复：\(text)"
        case .failed(let message):
            return message
        }
    }
}
