// The microphone permission mapping (WI-M2-M3; T-27: microphone only, no speech-recognition authorization). P-1.

import AVFAudio
import Testing
@testable import TendAI

@Suite("Speech permission (WI-M2-M3; T-27)")
struct SpeechPermissionTests {
    @Test("Every record permission maps to the neutral permission")
    func mapping() {
        #expect(SpeechPermission.map(.granted) == .allowed)
        #expect(SpeechPermission.map(.undetermined) == .notAsked)
        #expect(SpeechPermission.map(.denied) == .notAllowed)
    }
}
