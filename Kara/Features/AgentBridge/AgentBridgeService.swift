import Foundation
import Observation

@MainActor
@Observable
final class AgentBridgeService {
    var state: AgentBridgeState = .initializing
    var activeTurnID: UUID?
    var lastSeq: Int = 0
    var recentEvents: [AgentBridgeEvent] = []
    var lastRoute: AgentBridgeRoute?
    var lastRouteReason: String?
    var lastContext: AgentBridgeContext?

    private let eventStore: AgentBridgeEventStore
    private let router: AgentSessionRouter
    private var activeTask: Task<AgentBridgeRunResult, Never>?

    init(
        eventStore: AgentBridgeEventStore = AgentBridgeEventStore(),
        router: AgentSessionRouter = AgentSessionRouter()
    ) {
        self.eventStore = eventStore
        self.router = router
        if let lastTarget = router.lastSuccessfulTarget() {
            self.lastRoute = AgentBridgeRoute(
                target: lastTarget,
                reason: "上一次成功发送的 Agent/session"
            )
        }

        Task {
            await publish(.bridgeReady, turnID: nil, message: "Agent Bridge ready")
            await setState(.waiting, activeTurnID: nil)
            recentEvents = await eventStore.recent(limit: 40)
            lastSeq = recentEvents.last?.seq ?? 0
        }
    }

    func startTurn(
        text: String,
        screenshotURL: URL?,
        selectedTool: AIToolType?,
        enabledTools: Set<AIToolType>,
        selectedSession: AgentSession,
        forcedTarget: AgentTarget? = nil,
        onRequestReady: @MainActor @escaping (AgentDeliveryRequest) -> Void
    ) async -> AgentBridgeRunResult {
        if let activeTask {
            _ = await abort(reason: "新的请求开始，取消上一轮")
            _ = await activeTask.value
        }

        let turnID = UUID()
        activeTurnID = turnID
        await setState(.running, activeTurnID: turnID)

        let context = AgentBridgeContext.capture(
            projectPath: selectedSession.projectPath,
            screenshotURL: screenshotURL
        )
        lastContext = context

        let startConfig = AgentBridgeStartConfig(
            turnID: turnID,
            text: text,
            screenshotPath: screenshotURL?.path,
            selectedTool: selectedTool,
            enabledTools: Array(enabledTools).sorted { $0.rawValue < $1.rawValue },
            selectedSession: selectedSession,
            forcedTarget: forcedTarget,
            context: context
        )

        await eventStore.writeStartConfig(startConfig)
        await publish(.turnStarted, turnID: turnID, message: "Turn started", payload: [
            "textPreview": preview(text),
            "screenshotPath": screenshotURL?.path ?? ""
        ])
        await publish(.contextCaptured, turnID: turnID, message: "Context captured", payload: [
            "frontmostApplication": context.frontmostApplicationName ?? "",
            "bundleIdentifier": context.frontmostBundleIdentifier ?? "",
            "projectPath": context.projectPath ?? ""
        ])

        let routeResult = router.route(
            text: text,
            selectedTool: selectedTool,
            enabledTools: enabledTools,
            selectedSession: selectedSession,
            forcedTarget: forcedTarget
        )

        let route: AgentBridgeRoute
        switch routeResult {
        case .success(let value):
            route = value
        case .failure(let error):
            await publish(.turnFailed, turnID: turnID, message: error.message)
            await setState(.waiting, activeTurnID: nil)
            return AgentBridgeRunResult(
                turnID: turnID,
                request: nil,
                exitCode: 1,
                output: error.message,
                route: nil
            )
        }

        lastRouteReason = route.reason
        lastRoute = route
        await publish(.routed, turnID: turnID, message: route.reason, payload: [
            "tool": route.target.tool.rawValue,
            "session": route.target.session.externalID ?? "new",
            "projectPath": route.target.session.projectPath ?? ""
        ])

        let request = AgentDeliveryRequest(
            text: text,
            screenshotURL: screenshotURL,
            target: route.target
        )
        onRequestReady(request)

        await publish(.processStarted, turnID: turnID, message: "Agent process started", payload: [
            "tool": route.target.tool.rawValue
        ])

        let task = Task<AgentBridgeRunResult, Never> {
            let cliResult = await AgentCLIAdapter.run(request: request)
            return AgentBridgeRunResult(
                turnID: turnID,
                request: request,
                exitCode: cliResult.exitCode,
                output: cliResult.output,
                route: route
            )
        }
        activeTask = task
        let result = await task.value
        activeTask = nil

        await publish(.processFinished, turnID: turnID, message: "Agent process finished", payload: [
            "exitCode": "\(result.exitCode)"
        ])

        if result.exitCode == 0 {
            router.recordSuccess(route.target)
            await publish(.turnCompleted, turnID: turnID, message: "Turn completed", payload: [
                "tool": route.target.tool.rawValue
            ])
        } else {
            await publish(.turnFailed, turnID: turnID, message: result.output.isEmpty ? "Agent failed" : result.output, payload: [
                "tool": route.target.tool.rawValue,
                "exitCode": "\(result.exitCode)"
            ])
        }

        await setState(.waiting, activeTurnID: nil)
        return result
    }

    func appendUserMessage(_ text: String) async {
        guard let activeTurnID else { return }
        await publish(.userMessage, turnID: activeTurnID, message: text)
    }

    func abort(reason: String = "用户取消") async -> Bool {
        guard let activeTurnID else { return false }
        activeTask?.cancel()
        await publish(.turnAborted, turnID: activeTurnID, message: reason)
        await setState(.draining, activeTurnID: activeTurnID)
        return true
    }

    func detach() async {
        await publish(.turnDetached, turnID: activeTurnID, message: "Bridge detached")
        await setState(.done, activeTurnID: nil)
    }

    func replay(after sequence: Int) async -> [AgentBridgeEvent] {
        let events = await eventStore.replay(after: sequence)
        if let last = events.last {
            lastSeq = last.seq
        }
        await publish(.replay, turnID: activeTurnID, message: "Replayed events after \(sequence)", payload: [
            "count": "\(events.count)"
        ])
        return events
    }

    private func setState(_ newState: AgentBridgeState, activeTurnID: UUID?) async {
        state = newState
        self.activeTurnID = activeTurnID
        await eventStore.writeMeta(state: newState, activeTurnID: activeTurnID)
    }

    private func publish(
        _ kind: AgentBridgeEventKind,
        turnID: UUID?,
        message: String,
        payload: [String: String] = [:]
    ) async {
        let event = await eventStore.append(kind, turnID: turnID, message: message, payload: payload)
        lastSeq = event.seq
        recentEvents.append(event)
        if recentEvents.count > 40 {
            recentEvents.removeFirst(recentEvents.count - 40)
        }
    }

    private func preview(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 80 else { return trimmed }
        return String(trimmed.prefix(80)) + "..."
    }
}
