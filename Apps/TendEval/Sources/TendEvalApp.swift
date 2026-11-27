// TendEval: the debug-only eval harness (AC-M2-28). Scaffold from WI-M2-M1: its own bundle ID, Debug only, file
// sharing in Debug only, the frozen eval fixtures bundled, and its scheme's Archive action off (`project.yml`).
// The harness itself arrives in WI-M2-M7. AC-M2-09 Rule 6 scans this root (`ScanScope`: required).

import SwiftUI

@main
struct TendEvalApp: App {
    var body: some Scene {
        WindowGroup {
            Text(verbatim: "TendEval")
        }
    }
}
