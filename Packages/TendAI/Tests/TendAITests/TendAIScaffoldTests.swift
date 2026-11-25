// TendAI on macOS (`xcodebuild test -scheme TendAI -destination 'platform=macOS'`, plan B4). Scaffold from WI-M2-M1:
// it proves the package builds with Swift 6 and `-warnings-as-errors` and that its tests run. The mock and adapter
// tests arrive with WI-M2-M2…M6 (AC-M2-05, 07, 10, 24 adapter halves; AC-M2-13(b)).

import Testing
import TendAI

@Suite("TendAI scaffold (WI-M2-M1, AC-M2-13(b) groundwork)")
struct TendAIScaffoldTests {

    @Test("The TendAI module links and names itself")
    func moduleName() {
        #expect(TendAIModule.name == "TendAI")
    }
}
