import Foundation

enum SessionExportFormat: String, CaseIterable, Identifiable, Sendable {
    case markdown
    case txt

    var id: String { rawValue }

    var label: String {
        switch self {
        case .markdown:
            "Markdown"
        case .txt:
            "TXT"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown:
            "md"
        case .txt:
            "txt"
        }
    }
}

struct SessionExportOptions: Equatable, Sendable {
    var includesTranscript = true
    var includesTranslation = true
}

struct SessionExportPackage: Equatable, Sendable {
    var filename: String
    var contents: String
}

enum SessionExportError: LocalizedError, Equatable {
    case emptySelection
    case emptyContent
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            "请选择至少一种要导出的内容。"
        case .emptyContent:
            "当前记录还没有可导出的内容。"
        case .writeFailed(let message):
            "导出失败：\(message)"
        }
    }
}

struct SessionExportBuilder {
    func build(
        session: NoteSession,
        segments: [TranscriptSegment],
        format: SessionExportFormat,
        options: SessionExportOptions
    ) throws -> SessionExportPackage {
        guard options.includesTranscript || options.includesTranslation else {
            throw SessionExportError.emptySelection
        }

        let finalSegments = segments
            .filter(\.isFinal)
            .sortedByTranscriptOrder()

        let contentSections = switch format {
        case .markdown:
            markdownSections(
                segments: finalSegments,
                options: options
            )
        case .txt:
            txtSections(
                segments: finalSegments,
                options: options
            )
        }

        guard !contentSections.isEmpty else {
            throw SessionExportError.emptyContent
        }

        let sections = [header(for: session, format: format)] + contentSections
        let contents = sections
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return SessionExportPackage(
            filename: "\(Self.sanitizedFilename(session.title)).\(format.fileExtension)",
            contents: contents + "\n"
        )
    }

    private func markdownSections(
        segments: [TranscriptSegment],
        options: SessionExportOptions
    ) -> [String] {
        var sections: [String] = []

        if options.includesTranscript, !segments.isEmpty {
            sections.append("""
            ## 原文

            \(segments.map { "- [\(Self.timestampText($0.startTime))] \($0.text)" }.joined(separator: "\n"))
            """)
        }

        if options.includesTranslation, !segments.isEmpty {
            let translatedLines = segments.map { segment in
                "- [\(Self.timestampText(segment.startTime))] \(segment.translatedText?.nilIfBlank ?? Self.translationFallback(for: segment.translationStatus))"
            }
            sections.append("""
            ## 译文

            \(translatedLines.joined(separator: "\n"))
            """)
        }

        return sections
    }

    private func txtSections(
        segments: [TranscriptSegment],
        options: SessionExportOptions
    ) -> [String] {
        var sections: [String] = []

        if options.includesTranscript, !segments.isEmpty {
            sections.append("""
            原文

            \(segments.map { "[\(Self.timestampText($0.startTime))] \($0.text)" }.joined(separator: "\n"))
            """)
        }

        if options.includesTranslation, !segments.isEmpty {
            let translatedLines = segments.map { segment in
                "[\(Self.timestampText(segment.startTime))] \(segment.translatedText?.nilIfBlank ?? Self.translationFallback(for: segment.translationStatus))"
            }
            sections.append("""
            译文

            \(translatedLines.joined(separator: "\n"))
            """)
        }

        return sections
    }

    private func header(for session: NoteSession, format: SessionExportFormat) -> String {
        switch format {
        case .markdown:
            """
            # \(session.title)

            - 状态：\(session.status.label)
            - 时长：\(Self.durationText(session.duration))
            - 语言：\(session.sourceLanguageName) -> \(session.targetLanguageName)
            """
        case .txt:
            """
            \(session.title)
            状态：\(session.status.label)
            时长：\(Self.durationText(session.duration))
            语言：\(session.sourceLanguageName) -> \(session.targetLanguageName)
            """
        }
    }

    private static func timestampText(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private static func translationFallback(for status: TranslationStatus) -> String {
        switch status {
        case .notRequested:
            "未翻译"
        case .translating:
            "翻译中"
        case .translated:
            "译文为空"
        case .unavailable(let message), .failed(let message):
            message
        }
    }

    private static func sanitizedFilename(_ filename: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let sanitized = filename
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return sanitized.isEmpty ? "LiveNote" : sanitized
    }
}

private extension Array where Element == TranscriptSegment {
    func sortedByTranscriptOrder() -> [TranscriptSegment] {
        sorted { first, second in
            if first.startTime == second.startTime {
                return first.id.uuidString < second.id.uuidString
            }

            return first.startTime < second.startTime
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
