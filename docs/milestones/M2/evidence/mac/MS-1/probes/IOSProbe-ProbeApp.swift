import SwiftUI
@main
struct ProbeApp: App {
    var body: some Scene {
        WindowGroup {
            Text("WI-M2-M1 probe").task {
                let url = Bundle.main.url(forResource: "utterance", withExtension: "wav")!
                await runAllProbes(audioURL: url)
                exit(0)
            }
        }
    }
}
