import Foundation

struct AgentSessionRouter {
    private let defaultsKey = "Kara.AgentBridge.lastSuccessfulTarget"

    func route(
        text: String,
        selectedTool: AIToolType?,
        selectedSession: AgentSession,
        forcedTarget: AgentTarget?
    ) -> Result<AgentBridgeRoute, AgentBridgeRouteError> {
        if let forcedTarget {
            return .success(
                AgentBridgeRoute(
                    target: forcedTarget,
                    reason: "使用重试请求绑定的 Agent/session"
                )
            )
        }

        if let lastTarget = lastSuccessfulTarget(),
           lastTarget.tool.canSendMessages {
            return .success(
                AgentBridgeRoute(
                    target: lastTarget,
                    reason: "复用上一次成功发送的 Agent/session"
                )
            )
        }

        let tool = selectedTool?.baseTool
            ?? preferredInstalledTool()

        guard let tool else {
            return .failure(AgentBridgeRouteError(message: "未检测到可用 Agent CLI"))
        }

        guard let endpoint = AgentCLIAdapter.endpoint(for: tool, session: selectedSession) else {
            return .failure(AgentBridgeRouteError(message: "\(tool.displayName) 未检测到可用安装"))
        }

        let target = AgentTarget(
            tool: tool,
            endpoint: endpoint,
            session: selectedSession
        )

        return .success(
            AgentBridgeRoute(
                target: target,
                reason: selectedTool == nil ? "自动选择可用 Agent" : "使用当前选择的 Agent/session"
            )
        )
    }

    func recordSuccess(_ target: AgentTarget) {
        guard let data = try? JSONEncoder().encode(target) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    func lastSuccessfulTarget() -> AgentTarget? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let target = try? JSONDecoder().decode(AgentTarget.self, from: data),
              target.tool.canSendMessages
        else {
            return nil
        }
        return target
    }

    private func preferredInstalledTool() -> AIToolType? {
        [.codexCLI, .claudeCLI, .hermesCLI].first { $0.canSendMessages }
    }
}
