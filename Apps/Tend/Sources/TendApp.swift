// The Tend app target: a build skeleton with no product UI (M2 plan "Module and file layout"). It exists in M2 only so
// that AC-M2-28 can prove the Release and Archive products hold no TendEval (plan B6). It is never distributed in M2.

import SwiftUI

@main
struct TendApp: App {
    var body: some Scene {
        WindowGroup {
            Color.clear
        }
    }
}
