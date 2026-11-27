// TendAITestHost: a never-shipped iOS host app for `Packages/TendAI/HostedTests` (Keychain and `URLProtocol` tests
// need an app host; M2 plan "Module and file layout", B5). Its root view is the SP-1 speech screen
// (docs/milestones/M2/device-scripts/SP-1.md Part D4), which does nothing until a button is tapped, so the hosted
// tests are not changed by it. Not product UI; never archived.

import SwiftUI

@main
struct TendAITestHostApp: App {
    var body: some Scene {
        WindowGroup {
            SP1SpeechScreen()
        }
    }
}
