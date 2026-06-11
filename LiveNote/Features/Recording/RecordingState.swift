import Foundation

enum RecordingState: String, Sendable {
    case ready
    case recording
    case paused
    case processing

    var label: String {
        switch self {
        case .ready:
            "就绪"
        case .recording:
            "录音中"
        case .paused:
            "已暂停"
        case .processing:
            "整理中"
        }
    }

    var menuBarSystemImage: String {
        switch self {
        case .ready:
            "record.circle"
        case .recording:
            "record.circle.fill"
        case .paused:
            "pause.circle.fill"
        case .processing:
            "arrow.triangle.2.circlepath.circle"
        }
    }
}
