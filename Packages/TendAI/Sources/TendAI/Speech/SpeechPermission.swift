// The permission a voice capture needs (WI-M2-M3; plan "Speech-permission file"; AC-M2-09 Rule 5; T-27). P-1.
//
// T-27 (WI-M2-M1, 2026-11-25): `SpeechAnalyzer` with `SpeechTranscriber` or `DictationTranscriber` needs no
// speech-recognition authorization, so the Rule 5 exception is off and this file uses no API of the server-capable
// recogniser. Live capture needs only the microphone permission (`AVAudioApplication`, with
// `NSMicrophoneUsageDescription` in the app's Info.plist, which M3's app target adds). DS-1 and DS-2 confirm on device
// that the first capture shows the microphone prompt and no other.

import AVFAudio
import Foundation

/// Whether the app may record from the microphone.
public enum MicrophonePermission: Hashable, Sendable {
    case allowed
    /// The person has not been asked yet.
    case notAsked
    /// The person said no, or a policy does not allow it. M3 shows the calm way to turn it on in Settings.
    case notAllowed
}

public enum SpeechPermission {
    /// The microphone permission now, without asking.
    public static func microphone() -> MicrophonePermission {
        map(AVAudioApplication.shared.recordPermission)
    }

    /// Asks once if the person has not been asked; returns the permission after.
    public static func requestMicrophone() async -> MicrophonePermission {
        guard microphone() == .notAsked else { return microphone() }
        return await AVAudioApplication.requestRecordPermission() ? .allowed : .notAllowed
    }

    static func map(_ permission: AVAudioApplication.recordPermission) -> MicrophonePermission {
        switch permission {
        case .granted: .allowed
        case .undetermined: .notAsked
        case .denied: .notAllowed
        @unknown default: .notAllowed
        }
    }
}
