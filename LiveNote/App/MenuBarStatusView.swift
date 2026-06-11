import SwiftUI

enum MenuBarStatusMetrics {
    static let statusItemLength: CGFloat = 110
    static let capsuleWidth: CGFloat = 108
    static let dotWidth: CGFloat = 10
    static let elapsedWidth: CGFloat = 36
    static let badgeWidth: CGFloat = 24
}

enum MenuBarElapsedTimeFormatter {
    static func compactUnitString(from elapsedSeconds: TimeInterval) -> String {
        let totalSeconds = max(Int(elapsedSeconds), 0)
        let minute = 60
        let hour = minute * 60
        let day = hour * 24

        let value: Int
        let suffix: String

        switch totalSeconds {
        case day...:
            value = totalSeconds / day
            suffix = "d"
        case hour...:
            value = totalSeconds / hour
            suffix = "h"
        case minute...:
            value = totalSeconds / minute
            suffix = "m"
        default:
            value = totalSeconds
            suffix = "s"
        }

        return String(format: "%02d%@", min(value, 99), suffix)
    }
}

struct MenuBarCapsuleLabel: View {
    let viewModel: RecordingViewModel

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .strokeBorder(statusColor, lineWidth: 1.8)
                .background {
                    Circle()
                        .fill(statusDotFill)
                }
                .frame(width: MenuBarStatusMetrics.dotWidth, height: MenuBarStatusMetrics.dotWidth)

            Text(compactElapsedTime)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(statusColor)
                .frame(width: MenuBarStatusMetrics.elapsedWidth, alignment: .leading)

            Text(statusBadge)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(.black)
                .frame(width: MenuBarStatusMetrics.badgeWidth)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(badgeColor, in: Capsule())
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(width: MenuBarStatusMetrics.capsuleWidth)
        .background(.black, in: Capsule())
        .accessibilityLabel("LiveNote \(viewModel.recordingState.label), \(compactElapsedTime), \(statusBadge)")
    }

    private var compactElapsedTime: String {
        MenuBarElapsedTimeFormatter.compactUnitString(from: viewModel.elapsedSeconds)
    }

    private var statusBadge: String {
        switch viewModel.recordingState {
        case .ready:
            "RDY"
        case .recording:
            "REC"
        case .paused:
            "PAU"
        case .processing:
            "SYN"
        }
    }

    private var statusDotFill: Color {
        switch viewModel.recordingState {
        case .ready:
            .clear
        case .recording, .paused, .processing:
            statusColor.opacity(0.28)
        }
    }

    private var badgeColor: Color {
        switch viewModel.recordingState {
        case .ready:
            .green
        case .recording:
            .red.opacity(0.9)
        case .paused:
            .orange
        case .processing:
            .cyan
        }
    }

    private var statusColor: Color {
        switch viewModel.recordingState {
        case .ready:
            .green
        case .recording:
            .red
        case .paused:
            .orange
        case .processing:
            .blue
        }
    }

}

struct MenuBarStatusView: View {
    let viewModel: RecordingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: viewModel.recordingState.menuBarSystemImage)
                            .foregroundStyle(statusColor)

                        Text("LiveNote")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption.weight(.medium))

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(viewModel.recordingState.label)
                            .font(.system(size: 28, weight: .bold, design: .rounded))

                        Text(formattedElapsedTime)
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(statusColor)
                    }
                }

                Spacer()

                Text(statusBadge)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(badgeColor, in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(18)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("\(viewModel.sourceLanguageName) → \(viewModel.targetLanguageName) · 本机处理")
                    .font(.headline)

                currentUtteranceView

                HStack(spacing: 10) {
                    Button(recordToggleTitle) {
                        viewModel.toggleRecording()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canToggleRecording)

                    Button("停止") {
                        viewModel.stopRecording()
                    }
                    .disabled(!viewModel.canStopRecording)
                }

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            .padding(18)
        }
        .frame(width: 380)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var currentUtteranceView: some View {
        if let utterance = currentUtterance {
            VStack(alignment: .leading, spacing: 8) {
                MenuBarLiveTextLine(
                    title: "翻译前",
                    text: utterance.source,
                    isPlaceholder: utterance.sourceIsPlaceholder
                )

                MenuBarLiveTextLine(
                    title: "翻译后",
                    text: utterance.translation,
                    isPlaceholder: utterance.translationIsPlaceholder
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(statusDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var formattedElapsedTime: String {
        let minutes = Int(viewModel.elapsedSeconds) / 60
        let seconds = Int(viewModel.elapsedSeconds) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var statusBadge: String {
        switch viewModel.recordingState {
        case .ready:
            "READY"
        case .recording:
            "REC"
        case .paused:
            "PAUSE"
        case .processing:
            "SYNC"
        }
    }

    private var statusDescription: String {
        switch viewModel.recordingState {
        case .ready:
            "等待开始实时语音记录。"
        case .recording:
            "正在从麦克风采集音频并实时转写。"
        case .paused:
            "实时转写已暂停，已确认文本会保留。"
        case .processing:
            "正在整理当前录音状态。"
        }
    }

    private var currentUtterance: MenuBarLiveUtterance? {
        let liveText = viewModel.volatileText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !liveText.isEmpty {
            return MenuBarLiveUtterance(
                source: liveText,
                translation: "等待当前句稳定后翻译",
                sourceIsPlaceholder: false,
                translationIsPlaceholder: true
            )
        }

        guard let segment = viewModel.segments.last(where: \.isFinal) else {
            guard viewModel.recordingState == .recording else {
                return nil
            }

            return MenuBarLiveUtterance(
                source: "正在听取当前句",
                translation: "等待当前句出现",
                sourceIsPlaceholder: true,
                translationIsPlaceholder: true
            )
        }

        let translationText: String
        let translationIsPlaceholder: Bool
        if let translatedText = segment.translatedText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !translatedText.isEmpty {
            translationText = translatedText
            translationIsPlaceholder = false
        } else {
            translationText = Self.translationFallbackText(for: segment.translationStatus, targetLanguageName: viewModel.targetLanguageName)
            translationIsPlaceholder = true
        }

        return MenuBarLiveUtterance(
            source: segment.text,
            translation: translationText,
            sourceIsPlaceholder: false,
            translationIsPlaceholder: translationIsPlaceholder
        )
    }

    private static func translationFallbackText(for status: TranslationStatus, targetLanguageName: String) -> String {
        switch status {
        case .notRequested:
            "等待翻译为\(targetLanguageName)"
        case .translating:
            "正在生成\(targetLanguageName)译文"
        case .translated:
            "译文为空"
        case .unavailable(let message), .failed(let message):
            message
        }
    }

    private var recordToggleTitle: String {
        switch viewModel.recordingState {
        case .ready:
            "开始"
        case .recording:
            "暂停"
        case .paused:
            "继续"
        case .processing:
            "处理中"
        }
    }

    private var statusColor: Color {
        switch viewModel.recordingState {
        case .ready:
            .green
        case .recording:
            .red
        case .paused:
            .orange
        case .processing:
            .blue
        }
    }

    private var badgeColor: Color {
        switch viewModel.recordingState {
        case .ready:
            .yellow
        case .recording:
            .red.opacity(0.9)
        case .paused:
            .orange
        case .processing:
            .cyan
        }
    }
}

private struct MenuBarLiveUtterance {
    let source: String
    let translation: String
    let sourceIsPlaceholder: Bool
    let translationIsPlaceholder: Bool
}

private struct MenuBarLiveTextLine: View {
    let title: String
    let text: String
    let isPlaceholder: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(text)
                .font(.callout)
                .foregroundStyle(isPlaceholder ? .secondary : .primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}
