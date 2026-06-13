import Foundation
import Observation

enum AgentEndpoint: Equatable, Codable {
    case cli(command: String, arguments: [String])
}

struct AgentSession: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    let createdAt: Date
    var externalID: String?
    var sourceTool: AIToolType?
    var projectName: String?
    var projectPath: String?

    static let defaultTitle = "new session"

    static func makeDefault() -> AgentSession {
        AgentSession(
            id: UUID(),
            title: defaultTitle,
            createdAt: Date(),
            externalID: nil,
            sourceTool: nil,
            projectName: nil,
            projectPath: nil
        )
    }
}

struct AgentRecentSession: Identifiable, Equatable {
    let id: String
    let externalID: String
    let tool: AIToolType
    let title: String
    let updatedAt: Date
    let projectName: String?
    let projectPath: String?

    var displayTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: "zh-CN")
        return formatter.localizedString(for: updatedAt, relativeTo: Date())
    }

    var agentSession: AgentSession {
        AgentSession(
            id: UUID(uuidString: externalID) ?? UUID(),
            title: title,
            createdAt: updatedAt,
            externalID: externalID,
            sourceTool: tool,
            projectName: projectName,
            projectPath: projectPath
        )
    }
}

struct AgentTarget: Equatable, Codable {
    var tool: AIToolType
    var endpoint: AgentEndpoint
    var session: AgentSession
}

struct AgentDeliveryRequest: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let target: AgentTarget
    let createdAt = Date()
}

enum AgentDeliveryState: Equatable {
    case idle
    case transcribing
    case sending(AgentDeliveryRequest)
    case delivered(AgentDeliveryRequest)
    case running(AgentDeliveryRequest)
    case completed(AgentDeliveryRequest)
    case failed(String)

    var menuLabel: String? {
        switch self {
        case .idle:
            return nil
        case .transcribing:
            return "转写中"
        case .sending:
            return "发送中"
        case .delivered:
            return "已提交"
        case .running:
            return "执行中"
        case .completed:
            return "完成"
        case .failed:
            return "失败"
        }
    }

    var detailText: String {
        switch self {
        case .idle:
            return "语音会发送给当前 Agent"
        case .transcribing:
            return "正在整理语音文本"
        case .sending(let request):
            return "正在发送到 \(request.target.tool.compactDisplayName)"
        case .delivered(let request):
            return "已提交到 \(request.target.tool.compactDisplayName)"
        case .running(let request):
            return "\(request.target.tool.compactDisplayName) CLI 正在执行"
        case .completed(let request):
            return "\(request.target.tool.compactDisplayName) CLI 已完成"
        case .failed(let message):
            return message
        }
    }
}

struct AgentDeliveryResult: Equatable {
    let request: AgentDeliveryRequest?
    let state: AgentDeliveryState
}

/// Manages sending transcribed text to the selected AI tool.
@MainActor
@Observable
final class AIIntegrationService {
    var selectedTool: AIToolType? {
        didSet {
            persist()
            if oldValue?.baseTool != selectedTool?.baseTool {
                loadRecentSessionsForSelectedTool()
            }
        }
    }
    var selectedSession: AgentSession {
        didSet { persistSession() }
    }
    var deliveryState: AgentDeliveryState = .idle
    var recentSessions: [AgentRecentSession] = []
    var recentSessionsByTool: [AIToolType: [AgentRecentSession]] = [:]
    var loadingRecentSessionTools: Set<AIToolType> = []
    var lastResponse: String?
    var lastError: String?

    private let defaultsKey = "Kara.selectedAITool"
    private let sessionDefaultsKey = "Kara.selectedAgentSession"
    private var clearStateTask: Task<Void, Never>?
    private var recentSessionTasks: [AIToolType: Task<Void, Never>] = [:]
    nonisolated private static let cliTimeoutSeconds: TimeInterval = 180

    init() {
        if let raw = UserDefaults.standard.string(forKey: defaultsKey),
           let tool = AIToolType(rawValue: raw) {
            selectedTool = tool.baseTool
        }

        if let data = UserDefaults.standard.data(forKey: sessionDefaultsKey),
           let session = try? JSONDecoder().decode(AgentSession.self, from: data) {
            selectedSession = session
        } else {
            selectedSession = AgentSession.makeDefault()
        }

        if selectedTool == nil {
            selectedTool = preferredTool
        }

        loadRecentSessionsForSelectedTool()
    }

    /// Tools that can currently receive messages.
    var installedTools: [AIToolType] {
        AIToolType.allCases.filter { $0.canSendMessages }
    }

    var preferredTool: AIToolType? {
        selectedTool.flatMap {
            let normalizedTool = $0.baseTool
            return normalizedTool.canSendMessages ? normalizedTool : nil
        }
            ?? installedTools.first(where: { $0 == .codexCLI })
            ?? installedTools.first(where: { $0 == .claudeCLI })
            ?? installedTools.first(where: { $0 == .hermesCLI })
    }

    var statusDetailText: String {
        deliveryState.detailText
    }

    var canSendToSelectedTool: Bool {
        preferredTool?.canSendMessages == true
    }

    func refreshRecentSessions() {
        for tool in AIToolType.allCases {
            loadRecentSessions(for: tool)
        }
    }

    func loadRecentSessionsForSelectedTool() {
        guard let tool = selectedTool?.baseTool ?? preferredTool else {
            recentSessions = []
            return
        }

        loadRecentSessions(for: tool)
    }

    func loadRecentSessions(for tool: AIToolType) {
        let normalizedTool = tool.baseTool
        guard normalizedTool.canSendMessages else {
            recentSessionTasks[normalizedTool]?.cancel()
            loadingRecentSessionTools.remove(normalizedTool)
            recentSessionsByTool[normalizedTool] = []
            if preferredTool == normalizedTool {
                recentSessions = []
            }
            return
        }

        recentSessionTasks[normalizedTool]?.cancel()
        loadingRecentSessionTools.insert(normalizedTool)
        recentSessionsByTool[normalizedTool] = []
        if preferredTool == normalizedTool {
            recentSessions = []
        }

        recentSessionTasks[normalizedTool] = Task { [weak self] in
            let sessions = await Task.detached(priority: .userInitiated) {
                AgentRecentSessionReader.recentSessions(for: normalizedTool, limit: 5)
            }.value

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self else { return }
                self.loadingRecentSessionTools.remove(normalizedTool)
                self.recentSessionsByTool[normalizedTool] = sessions
                if self.preferredTool == normalizedTool {
                    self.recentSessions = sessions
                }
            }
        }
    }

    func selectRecentSession(_ session: AgentRecentSession) {
        selectedTool = session.tool
        selectedSession = session.agentSession
    }

    func clearSelectedSession(for tool: AIToolType) {
        selectedTool = tool
        selectedSession = AgentSession(
            id: UUID(),
            title: AgentSession.defaultTitle,
            createdAt: Date(),
            externalID: nil,
            sourceTool: tool,
            projectName: nil,
            projectPath: nil
        )
    }

    func markTranscribing() {
        clearStateTask?.cancel()
        deliveryState = .transcribing
    }

    func markFailed(_ message: String) {
        _ = fail(message)
    }

    /// Send the given text to the currently selected AI tool.
    func sendText(_ text: String) {
        Task {
            _ = await deliverText(text)
        }
    }

    func deliverTextForReply(_ text: String) async throws -> String {
        Self.log("deliverTextForReply start: \(Self.previewText(text))")
        let result = await deliverText(text)

        switch result.state {
        case .completed:
            let reply = lastResponse?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Self.log("deliverTextForReply completed: \(Self.previewText(reply))")
            return reply.isEmpty ? "已执行完成" : reply
        case .failed(let message):
            Self.log("deliverTextForReply failed: \(message)")
            throw AIReplyError(message: message)
        default:
            Self.log("deliverTextForReply ended in non-final state")
            throw AIReplyError(message: "AI 执行未完成")
        }
    }

    @discardableResult
    func deliverText(_ text: String) async -> AgentDeliveryResult {
        clearStateTask?.cancel()

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return fail("没有可发送的文本")
        }

        guard let tool = preferredTool else {
            Self.log("deliverText failed: no selected tool")
            return fail("未选择 AI 工具")
        }

        if selectedTool != tool {
            selectedTool = tool
        }

        lastError = nil
        lastResponse = nil

        guard let endpoint = endpoint(for: tool) else {
            Self.log("deliverText failed: endpoint unavailable for \(tool.rawValue)")
            return fail("\(tool.displayName) 未检测到可用安装")
        }

        let target = AgentTarget(tool: tool, endpoint: endpoint, session: selectedSession)
        let request = AgentDeliveryRequest(text: trimmedText, target: target)

        deliveryState = .sending(request)
        deliveryState = .running(request)
        Self.log("deliverText running: tool=\(tool.rawValue), session=\(selectedSession.externalID ?? "new")")
        let result = await runCLI(request: request)
        Self.log("deliverText CLI exited: code=\(result.exitCode), output=\(Self.previewText(result.output))")

        if result.exitCode == 0 {
            lastResponse = result.output
            deliveryState = .completed(request)
            scheduleStateReset()
            return AgentDeliveryResult(request: request, state: deliveryState)
        }

        return fail(result.output.isEmpty ? "CLI 执行失败，退出码 \(result.exitCode)" : result.output)
    }

    private func endpoint(for tool: AIToolType) -> AgentEndpoint? {
        guard tool.isCommandLine,
              let cliURL = tool.cliExecutableURL
        else {
            return nil
        }
        return .cli(command: cliURL.path, arguments: cliArguments(for: tool))
    }

    // MARK: - CLI

    private func cliArguments(for tool: AIToolType) -> [String] {
        switch tool {
        case .codexDesktop, .codexCLI:
            if selectedSession.sourceTool?.baseTool == .codexCLI,
               let externalID = selectedSession.externalID,
               !externalID.isEmpty {
                return ["exec", "resume", "--skip-git-repo-check", externalID]
            }
            return ["exec", "--skip-git-repo-check", "--sandbox", "read-only"]
        case .claudeDesktop, .claudeCLI:
            var arguments = ["-p"]
            if selectedSession.sourceTool?.baseTool == .claudeCLI,
               let externalID = selectedSession.externalID,
               !externalID.isEmpty,
               selectedSession.projectPath != nil {
                arguments += ["--resume", externalID]
            }
            return arguments
        case .hermesDesktop, .hermesCLI:
            var arguments = [
                "chat",
                "-Q",
                "--ignore-rules",
                "--max-turns", "3"
            ]
            if selectedSession.sourceTool?.baseTool == .hermesCLI,
               let externalID = selectedSession.externalID,
               !externalID.isEmpty {
                arguments += ["--resume", externalID]
            }
            arguments += ["-q"]
            return arguments
        }
    }

    private func runCLI(request: AgentDeliveryRequest) async -> CLIExecutionResult {
        guard case .cli(let command, let arguments) = request.target.endpoint else {
            return CLIExecutionResult(exitCode: 1, output: "当前目标不是 CLI")
        }

        let prompt = request.text
        let outputFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kara-codex-\(request.id.uuidString).txt")
        let shouldCaptureCodexLastMessage = request.target.tool.baseTool == .codexCLI

        return await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command)

            var processArguments = arguments
            if shouldCaptureCodexLastMessage {
                if processArguments.count >= 2,
                   processArguments[0] == "exec",
                   processArguments[1] == "resume" {
                    processArguments.insert(contentsOf: ["--output-last-message", outputFileURL.path], at: 2)
                } else {
                    processArguments += ["--output-last-message", outputFileURL.path]
                }
            }
            process.arguments = processArguments + [prompt]
            process.currentDirectoryURL = Self.workingDirectoryURL(for: request.target.session)

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            let outputCapture = PipeCapture()
            let errorCapture = PipeCapture()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    outputCapture.append(data)
                }
            }
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    errorCapture.append(data)
                }
            }

            do {
                Self.log("runCLI start: \(command) \(processArguments.joined(separator: " ")); cwd=\(process.currentDirectoryURL?.path ?? "")")
                try process.run()
                let deadline = Date().addingTimeInterval(Self.cliTimeoutSeconds)
                while process.isRunning && Date() < deadline {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                if process.isRunning {
                    process.terminate()
                    try? await Task.sleep(for: .milliseconds(500))
                    if process.isRunning {
                        process.interrupt()
                    }
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    Self.log("runCLI timeout after \(Int(Self.cliTimeoutSeconds))s")
                    return CLIExecutionResult(
                        exitCode: 124,
                        output: "Agent 执行超时，请稍后重试或换一个更具体的问题"
                    )
                }
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                let output = String(
                    data: outputCapture.snapshot(),
                    encoding: .utf8
                ) ?? ""
                let error = String(
                    data: errorCapture.snapshot(),
                    encoding: .utf8
                ) ?? ""
                let cleanOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanError = error.trimmingCharacters(in: .whitespacesAndNewlines)

                let codexLastMessage = shouldCaptureCodexLastMessage
                    ? (try? String(contentsOf: outputFileURL, encoding: .utf8))
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    : nil
                let successfulOutput = [codexLastMessage, cleanOutput]
                    .compactMap { $0 }
                    .first { !$0.isEmpty } ?? cleanError
                let failedOutput = [cleanOutput, cleanError]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")

                try? FileManager.default.removeItem(at: outputFileURL)
                Self.log("runCLI finished: status=\(process.terminationStatus)")
                return CLIExecutionResult(
                    exitCode: process.terminationStatus,
                    output: process.terminationStatus == 0 ? successfulOutput : failedOutput
                )
            } catch {
                Self.log("runCLI error: \(error.localizedDescription)")
                return CLIExecutionResult(exitCode: 1, output: error.localizedDescription)
            }
        }.value
    }

    nonisolated private static func workingDirectoryURL(for session: AgentSession) -> URL {
        guard let projectPath = session.projectPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !projectPath.isEmpty
        else {
            return FileManager.default.homeDirectoryForCurrentUser
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: projectPath, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return FileManager.default.homeDirectoryForCurrentUser
        }

        return URL(fileURLWithPath: projectPath)
    }

    // MARK: - Helpers

    private func fail(_ message: String) -> AgentDeliveryResult {
        lastError = message
        deliveryState = .failed(message)
        scheduleStateReset()
        return AgentDeliveryResult(request: nil, state: deliveryState)
    }

    private func scheduleStateReset() {
        clearStateTask?.cancel()
        clearStateTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.deliveryState = .idle
            }
        }
    }

    nonisolated private static func previewText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 60 else { return trimmed }
        return String(trimmed.prefix(60)) + "..."
    }

    nonisolated private static func log(_ message: String) {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Kara", isDirectory: true)
        let url = directory.appendingPathComponent("agent-cli.log")
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

    private func persist() {
        if let tool = selectedTool {
            UserDefaults.standard.set(tool.rawValue, forKey: defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
    }

    private func persistSession() {
        guard let data = try? JSONEncoder().encode(selectedSession) else {
            return
        }
        UserDefaults.standard.set(data, forKey: sessionDefaultsKey)
    }
}

private struct CLIExecutionResult: Equatable {
    let exitCode: Int32
    let output: String
}

private final class PipeCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        let copy = data
        lock.unlock()
        return copy
    }
}

private struct AIReplyError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

private enum AgentRecentSessionReader {
    static func recentSessions(for tool: AIToolType, limit: Int) -> [AgentRecentSession] {
        switch tool.baseTool {
        case .codexCLI:
            return codexSessions(for: tool, limit: limit)
        case .claudeCLI:
            return claudeSessions(for: tool, limit: limit)
        case .hermesCLI:
            return hermesSessions(for: tool, limit: limit)
        case .claudeDesktop, .codexDesktop, .hermesDesktop:
            return []
        }
    }

    private static func codexSessions(for tool: AIToolType, limit: Int) -> [AgentRecentSession] {
        let url = homeURL.appendingPathComponent(".codex/session_index.jsonl")
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        return content
            .split(separator: "\n")
            .compactMap { line -> AgentRecentSession? in
                guard let data = String(line).data(using: .utf8),
                      let record = try? JSONDecoder.iso8601Flexible.decode(CodexSessionRecord.self, from: data)
                else {
                    return nil
                }

                return AgentRecentSession(
                    id: record.id,
                    externalID: record.id,
                    tool: tool,
                    title: cleanTitle(record.threadName, fallback: "Codex session"),
                    updatedAt: record.updatedAt,
                    projectName: nil,
                    projectPath: nil
                )
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { $0 }
    }

    private static func claudeSessions(for tool: AIToolType, limit: Int) -> [AgentRecentSession] {
        let projectsURL = homeURL.appendingPathComponent(".claude/projects")
        guard let files = recursiveJSONLFiles(in: projectsURL) else {
            return []
        }

        return files
            .compactMap { claudeSession(from: $0, tool: tool) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { $0 }
    }

    private static func claudeSession(from url: URL, tool: AIToolType) -> AgentRecentSession? {
        let sessionID = url.deletingPathExtension().lastPathComponent
        let updatedAt = fileModifiedDate(url) ?? Date.distantPast

        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return AgentRecentSession(
                id: sessionID,
                externalID: sessionID,
                tool: tool,
                title: cleanTitle(sessionID, fallback: "Claude session"),
                updatedAt: updatedAt,
                projectName: projectName(fromClaudeProjectURL: url),
                projectPath: nil
            )
        }

        var fallbackTitle: String?
        var sessionProjectName = projectName(fromClaudeProjectURL: url)
        var sessionProjectPath: String?
        for line in content.split(separator: "\n").prefix(80) {
            guard let object = jsonObject(from: String(line)) else {
                continue
            }

            if let cwd = object["cwd"] as? String {
                if sessionProjectPath == nil {
                    sessionProjectPath = cwd
                }
                if sessionProjectName == nil {
                    sessionProjectName = projectName(fromPath: cwd)
                }
            }

            if object["type"] as? String == "ai-title",
               let title = object["aiTitle"] as? String {
                let externalID = object["sessionId"] as? String ?? sessionID
                return AgentRecentSession(
                    id: externalID,
                    externalID: externalID,
                    tool: tool,
                    title: cleanTitle(title, fallback: "Claude session"),
                    updatedAt: updatedAt,
                    projectName: sessionProjectName,
                    projectPath: sessionProjectPath
                )
            }

            if fallbackTitle == nil,
               object["type"] as? String == "user",
               let message = object["message"] as? [String: Any] {
                fallbackTitle = textFromClaudeContent(message["content"])
            }

            if fallbackTitle == nil,
               object["type"] as? String == "queue-operation",
               let content = object["content"] as? String {
                fallbackTitle = content
            }
        }

        return AgentRecentSession(
            id: sessionID,
            externalID: sessionID,
            tool: tool,
            title: cleanTitle(fallbackTitle ?? sessionID, fallback: "Claude session"),
            updatedAt: updatedAt,
            projectName: sessionProjectName,
            projectPath: sessionProjectPath
        )
    }

    private static func hermesSessions(for tool: AIToolType, limit: Int) -> [AgentRecentSession] {
        let sessionsURL = homeURL.appendingPathComponent(".hermes/sessions")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: sessionsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { hermesSession(from: $0, tool: tool) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { $0 }
    }

    private static func hermesSession(from url: URL, tool: AIToolType) -> AgentRecentSession? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let sessionID = object["session_id"] as? String
            ?? url.deletingPathExtension().lastPathComponent
        let updatedAt = (object["timestamp"] as? String).flatMap(parseDate)
            ?? fileModifiedDate(url)
            ?? Date.distantPast

        var title: String?
        if let request = object["request"] as? [String: Any],
           let body = request["body"] as? [String: Any],
           let messages = body["messages"] as? [[String: Any]] {
            title = messages.reversed().compactMap { message -> String? in
                guard message["role"] as? String == "user" else {
                    return nil
                }
                return message["content"] as? String
            }.first
        }

        return AgentRecentSession(
            id: "\(sessionID)-\(Int(updatedAt.timeIntervalSince1970))-\(url.deletingPathExtension().lastPathComponent)",
            externalID: sessionID,
            tool: tool,
            title: cleanTitle(title ?? sessionID, fallback: "Hermes session"),
            updatedAt: updatedAt,
            projectName: projectName(fromHermesObject: object),
            projectPath: projectPath(fromHermesObject: object)
        )
    }

    private static func recursiveJSONLFiles(in url: URL) -> [URL]? {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jsonl" }
    }

    private static func fileModifiedDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private static func jsonObject(from line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func textFromClaudeContent(_ content: Any?) -> String? {
        if let text = content as? String {
            return text
        }

        if let parts = content as? [[String: Any]] {
            return parts.compactMap { part in
                part["text"] as? String
            }.joined(separator: " ")
        }

        return nil
    }

    private static func cleanTitle(_ title: String?, fallback: String) -> String {
        let cleaned = (title ?? fallback)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else {
            return fallback
        }

        return String(cleaned.prefix(42))
    }

    private static func projectName(fromPath path: String?) -> String? {
        guard let path,
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? nil : name
    }

    private static func projectName(fromClaudeProjectURL url: URL) -> String? {
        let folder = url.deletingLastPathComponent().lastPathComponent
        guard folder.hasPrefix("-") else {
            return nil
        }

        let components = folder
            .split(separator: "-")
            .map(String.init)
            .filter { !$0.isEmpty }
        return components.last
    }

    private static func projectName(fromHermesObject object: [String: Any]) -> String? {
        for key in ["project", "workspace", "cwd", "directory", "root", "repo", "repository"] {
            if let value = object[key] as? String,
               let projectName = projectName(fromPath: value) {
                return projectName
            }
        }
        return nil
    }

    private static func projectPath(fromHermesObject object: [String: Any]) -> String? {
        for key in ["project", "workspace", "cwd", "directory", "root", "repo", "repository"] {
            if let value = object[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private static func parseDate(_ string: String) -> Date? {
        JSONDecoder.dateDecodingStrategyDate(from: string)
    }

    private static var homeURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }
}

private struct CodexSessionRecord: Decodable {
    let id: String
    let threadName: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case threadName = "thread_name"
        case updatedAt = "updated_at"
    }
}

private extension JSONDecoder {
    static var iso8601Flexible: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = dateDecodingStrategyDate(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported date format: \(value)"
            )
        }
        return decoder
    }

    static func dateDecodingStrategyDate(from value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let standardFormatter = ISO8601DateFormatter()
        standardFormatter.formatOptions = [.withInternetDateTime]
        if let date = standardFormatter.date(from: value) {
            return date
        }

        let hermesFormatter = DateFormatter()
        hermesFormatter.locale = Locale(identifier: "en_US_POSIX")
        hermesFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        return hermesFormatter.date(from: value)
    }
}
