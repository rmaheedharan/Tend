// TendAIHostedTests in the iOS Simulator, hosted by `TendAITestHost` (plan B5). Scaffold from WI-M2-M1: it proves the
// host app launches and the TendAI package links into a hosted test bundle. The Keychain (AC-M2-18(a), AC-M2-21) and
// `URLProtocol` transport (AC-M2-22, AC-M2-23) tests arrive with WI-M2-M4 and WI-M2-M5.

import Foundation
import Testing
import TendAI

@Suite("TendAI hosted scaffold (WI-M2-M1, AC-M2-13(b) groundwork)")
struct TendAIHostedScaffoldTests {

    @Test("The tests run inside the TendAITestHost app")
    func hostApp() {
        #expect(Bundle.main.bundleIdentifier == "com.tend.aitesthost")
    }

    @Test("The TendAI module links into the hosted test bundle")
    func moduleName() {
        #expect(TendAIModule.name == "TendAI")
    }
}
