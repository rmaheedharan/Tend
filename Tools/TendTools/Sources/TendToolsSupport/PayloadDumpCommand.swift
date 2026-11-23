// `tend-payload-dump` (plan "Real provider recordings", WI-M2-M6): prints the request body the payload builder makes
// for the fixed Outcome sentence with an empty household, so the owner can record a real provider stream with `curl`.
//
// STUB. The payload builder is WI-M2-10, which is not built yet. Until it is, this command checks its arguments and
// exits 3 with a plain message; it prints no body. WI-M2-10 replaces the body of `run` with the builder call. It never
// takes, reads or prints a key (the owner types the key into `curl`).

import Foundation

public enum PayloadDumpCommand {

    public static let usage = """
        usage: tend-payload-dump --provider <openai|anthropic|gemini> --outcome-sample
          Prints the request body for the brief's Outcome sentence with an empty household (no rooms, no titles).
        exit: 0 body printed, 3 payload builder not built yet (WI-M2-10), 64 usage error

        """

    public static let providers: Set<String> = ["openai", "anthropic", "gemini"]
    public static let exitNotBuilt: Int32 = 3

    public static func run(_ arguments: [String], io: ToolIO) -> Int32 {
        do throws(UsageError) {
            let parsed = try ParsedArguments(arguments, options: ["provider"], flags: ["outcome-sample", "help"])
            if parsed.flags.contains("help") { io.standardOutput(usage); return 0 }
            let provider = try parsed.required("provider")
            guard providers.contains(provider) else { throw UsageError("unknown provider: \(provider)") }
            guard parsed.flags.contains("outcome-sample") else { throw UsageError("--outcome-sample is required") }
        } catch {
            io.standardError("tend-payload-dump: \(error.message)\n\(usage)")
            return EvalScoreCommand.exitUsage
        }
        io.standardError("tend-payload-dump: the payload builder is not built yet (WI-M2-10); no body printed.\n")
        return exitNotBuilt
    }
}
