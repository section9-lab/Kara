import Foundation

struct AgentSessionRouter {
    private let defaultsKey = "Kara.AgentBridge.lastSuccessfulTarget"

    func route(
        text: String,
        selectedTool: AIToolType?,
        enabledTools: Set<AIToolType>,
        selectedSession: AgentSession,
        forcedTarget: AgentTarget?
    ) -> Result<AgentBridgeRoute, AgentBridgeRouteError> {
        if let forcedTarget {
            guard enabledTools.contains(forcedTarget.tool.baseTool) else {
                return .failure(AgentBridgeRouteError(message: "\(forcedTarget.tool.displayName) is disabled in Settings"))
            }
            return .success(
                AgentBridgeRoute(
                    target: forcedTarget,
                    reason: "Using the Agent/session bound to this retry"
                )
            )
        }

        if let lastTarget = lastSuccessfulTarget(),
           lastTarget.tool.canSendMessages,
           enabledTools.contains(lastTarget.tool.baseTool) {
            return .success(
                AgentBridgeRoute(
                    target: lastTarget,
                    reason: "Reusing the last successful Agent/session"
                )
            )
        }

        let selectedBaseTool = selectedTool?.baseTool
        let tool = selectedBaseTool.flatMap {
            enabledTools.contains($0) ? $0 : nil
        } ?? preferredInstalledTool(enabledTools: enabledTools)

        guard let tool else {
            return .failure(AgentBridgeRouteError(message: "No available Agent CLI detected"))
        }

        guard let endpoint = AgentCLIAdapter.endpoint(for: tool, session: selectedSession) else {
            return .failure(AgentBridgeRouteError(message: "\(tool.displayName) installation was not detected"))
        }

        let target = AgentTarget(
            tool: tool,
            endpoint: endpoint,
            session: selectedSession
        )

        return .success(
            AgentBridgeRoute(
                target: target,
                reason: selectedTool == nil ? "Automatically selected an available Agent" : "Using the current Agent/session"
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

    private func preferredInstalledTool(enabledTools: Set<AIToolType>) -> AIToolType? {
        [.codexCLI, .claudeCLI, .hermesCLI].first {
            $0.canSendMessages && enabledTools.contains($0)
        }
    }
}
