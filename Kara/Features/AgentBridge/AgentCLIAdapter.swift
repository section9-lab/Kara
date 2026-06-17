import Foundation

struct AgentCLIExecutionResult: Equatable {
    let exitCode: Int32
    let output: String
}

enum AgentCLIAdapter {
    nonisolated static let timeoutSeconds: TimeInterval = 180

    static func endpoint(for tool: AIToolType, session: AgentSession) -> AgentEndpoint? {
        guard tool.isCommandLine,
              let cliURL = tool.cliExecutableURL
        else {
            return nil
        }
        return .cli(command: cliURL.path, arguments: cliArguments(for: tool, session: session))
    }

    static func run(request: AgentDeliveryRequest) async -> AgentCLIExecutionResult {
        guard case .cli(let command, let arguments) = request.target.endpoint else {
            return AgentCLIExecutionResult(exitCode: 1, output: "当前目标不是 CLI")
        }

        let prompt = promptText(for: request)
        let outputFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kara-codex-\(request.id.uuidString).txt")
        let shouldCaptureCodexLastMessage = request.target.tool.baseTool == .codexCLI
        let shouldSendPromptViaStdin = request.target.tool.baseTool == .codexCLI

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

            if request.target.tool.baseTool == .codexCLI,
               let screenshotURL = request.screenshotURL,
               FileManager.default.fileExists(atPath: screenshotURL.path) {
                insertCodexImageArgument(screenshotURL.path, into: &processArguments)
                log("attaching image: \(screenshotURL.path)")
            } else if request.target.tool.baseTool == .claudeCLI,
                      let screenshotURL = request.screenshotURL,
                      FileManager.default.fileExists(atPath: screenshotURL.path) {
                insertClaudeScreenshotDirectory(screenshotURL.deletingLastPathComponent().path, into: &processArguments)
                log("exposing screenshot directory to Claude: \(screenshotURL.deletingLastPathComponent().path)")
            } else if request.screenshotURL != nil {
                log("screenshot available but no image argument for tool=\(request.target.tool.rawValue)")
            }

            process.arguments = shouldSendPromptViaStdin ? processArguments : processArguments + [prompt]
            process.currentDirectoryURL = workingDirectoryURL(for: request.target.session)

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            let inputPipe = Pipe()
            let outputCapture = BridgePipeCapture()
            let errorCapture = BridgePipeCapture()
            if shouldSendPromptViaStdin {
                process.standardInput = inputPipe
            }
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
                let promptSource = shouldSendPromptViaStdin ? "stdin" : "argv"
                log("start: \(command) \(processArguments.joined(separator: " ")); prompt=\(promptSource); cwd=\(process.currentDirectoryURL?.path ?? "")")
                try process.run()
                if shouldSendPromptViaStdin {
                    try inputPipe.fileHandleForWriting.write(contentsOf: Data(prompt.utf8))
                    try inputPipe.fileHandleForWriting.close()
                }

                let deadline = Date().addingTimeInterval(timeoutSeconds)
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
                    log("timeout after \(Int(timeoutSeconds))s")
                    return AgentCLIExecutionResult(
                        exitCode: 124,
                        output: "Agent 执行超时，请稍后重试或换一个更具体的问题"
                    )
                }

                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                let output = String(data: outputCapture.snapshot(), encoding: .utf8) ?? ""
                let error = String(data: errorCapture.snapshot(), encoding: .utf8) ?? ""
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
                log("finished: status=\(process.terminationStatus)")
                return AgentCLIExecutionResult(
                    exitCode: process.terminationStatus,
                    output: process.terminationStatus == 0 ? successfulOutput : failedOutput
                )
            } catch {
                log("error: \(error.localizedDescription)")
                return AgentCLIExecutionResult(exitCode: 1, output: error.localizedDescription)
            }
        }.value
    }

    private static func cliArguments(for tool: AIToolType, session: AgentSession) -> [String] {
        switch tool.baseTool {
        case .codexCLI:
            if session.sourceTool?.baseTool == .codexCLI,
               let externalID = session.externalID,
               !externalID.isEmpty {
                return ["exec", "resume", "--skip-git-repo-check", externalID]
            }
            return ["exec", "--skip-git-repo-check", "--sandbox", "read-only"]
        case .claudeCLI:
            var arguments = ["-p"]
            if session.sourceTool?.baseTool == .claudeCLI,
               let externalID = session.externalID,
               !externalID.isEmpty,
               session.projectPath != nil {
                arguments += ["--resume", externalID]
            }
            return arguments
        case .hermesCLI:
            var arguments = [
                "chat",
                "-Q",
                "--ignore-rules",
                "--max-turns", "3"
            ]
            if session.sourceTool?.baseTool == .hermesCLI,
               let externalID = session.externalID,
               !externalID.isEmpty {
                arguments += ["--resume", externalID]
            }
            arguments += ["-q"]
            return arguments
        case .claudeDesktop, .codexDesktop, .hermesDesktop:
            return []
        }
    }

    private static func promptText(for request: AgentDeliveryRequest) -> String {
        guard let screenshotURL = request.screenshotURL else {
            return request.text
        }

        if request.target.tool.baseTool == .codexCLI {
            return """
            语音转写内容：
            \(request.text)

            同一时刻的屏幕截图已作为图片附件随本次请求发送。

            请结合语音转写和截图理解我的意图并执行。
            """
        }

        if request.target.tool.baseTool == .claudeCLI {
            return """
            语音转写内容：
            \(request.text)

            同一时刻的屏幕截图已保存为 PNG 文件：
            \(screenshotURL.path)

            这个截图目录已经通过 --add-dir 授权给你读取。请读取这张截图，并结合语音转写理解我的意图并执行。
            """
        }

        return """
        语音转写内容：
        \(request.text)

        同一时刻的屏幕截图已保存为 PNG 文件：
        \(screenshotURL.path)

        请结合语音转写和这张截图理解我的意图并执行。
        """
    }

    private static func workingDirectoryURL(for session: AgentSession) -> URL {
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

    private static func insertCodexImageArgument(_ path: String, into arguments: inout [String]) {
        if arguments.count >= 2,
           arguments[0] == "exec",
           arguments[1] == "resume" {
            arguments.insert(contentsOf: ["--image", path], at: 2)
        } else {
            arguments += ["--image", path]
        }
    }

    private static func insertClaudeScreenshotDirectory(_ path: String, into arguments: inout [String]) {
        guard !arguments.contains(path) else { return }
        arguments += ["--add-dir", path]
    }

    private static func log(_ message: String) {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Kara", isDirectory: true)
        let url = directory.appendingPathComponent("agent-bridge.log")
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
            print("[Kara] AgentBridge \(message)")
        }
    }
}

private final class BridgePipeCapture: @unchecked Sendable {
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
