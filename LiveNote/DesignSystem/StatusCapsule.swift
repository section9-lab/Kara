import SwiftUI

struct StatusCapsule: View {
    let recordingState: RecordingState
    let elapsedSeconds: TimeInterval
    let sourceLanguage: String
    let targetLanguage: String?
    let processingMode: String

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(recordingState.label)
                .fontWeight(.medium)

            Divider()
                .frame(height: 14)

            Text(Self.timeFormatter.string(from: elapsedSeconds) ?? "00:00")
                .monospacedDigit()

            Divider()
                .frame(height: 14)

            Text(languageText)

            Divider()
                .frame(height: 14)

            Text(processingMode)
        }
        .font(.caption)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.quaternary, lineWidth: 1)
        }
        .help("查看录音、语言和本机处理状态")
    }

    private var statusColor: Color {
        switch recordingState {
        case .ready:
            .secondary
        case .recording:
            .red
        case .paused:
            .orange
        case .processing:
            .blue
        }
    }

    private var languageText: String {
        guard let targetLanguage else {
            return sourceLanguage
        }

        return "\(sourceLanguage) → \(targetLanguage)"
    }

    private static let timeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter
    }()
}
