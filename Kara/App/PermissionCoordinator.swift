import AVFAudio
import Foundation

enum MicrophonePermissionStatus: Sendable {
    case undetermined
    case denied
    case granted

    init(_ permission: AVAudioApplication.recordPermission) {
        switch permission {
        case .undetermined:
            self = .undetermined
        case .denied:
            self = .denied
        case .granted:
            self = .granted
        @unknown default:
            self = .denied
        }
    }
}

enum PermissionCoordinator {
    static var microphoneStatus: MicrophonePermissionStatus {
        MicrophonePermissionStatus(AVAudioApplication.shared.recordPermission)
    }

    static func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
