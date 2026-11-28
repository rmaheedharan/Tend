// TendEval: the debug-only eval harness (AC-M2-28; WI-M2-M7). Its own bundle ID, Debug only, file sharing in Debug
// only, the frozen eval fixtures bundled, its scheme's Archive action off, and a build-phase guard that stops any
// non-Debug build (`project.yml`). AC-M2-09 Rule 6 scans this root (`ScanScope`: required).

import SwiftUI

@main
struct TendEvalApp: App {
    var body: some Scene {
        WindowGroup {
            EvalRootView()
        }
    }
}
