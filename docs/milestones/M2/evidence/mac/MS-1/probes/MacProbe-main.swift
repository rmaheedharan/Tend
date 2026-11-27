import Foundation
let url = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "utterance.wav")
await runAllProbes(audioURL: url)
