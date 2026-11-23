// `tend-payload-dump` (plan "Real provider recordings", WI-M2-M6): prints the request body the payload builder makes
// for the brief's fixed Outcome sentence with an empty household (no rooms, no titles), so the owner can record a real
// provider stream with `curl`. The body is the WI-M2-10 golden body `g1-outcome-empty-<provider>.body.json`, byte for
// byte (a TendTools test checks it). It prints the body only, with no newline after it, and the provider's path and
// query on standard error. It never takes, reads or prints a key: the owner types the key into `curl`.

import Foundation
import TendIngestion

public enum PayloadDumpCommand {

    public static let usage = """
        usage: tend-payload-dump --provider <openai|anthropic|gemini> --outcome-sample
          Prints the request body for the brief's Outcome sentence with an empty household (no rooms, no titles)
          to standard output, and the request's method, host, path and query to standard error.
        exit: 0 body printed, 64 usage error

        """

    public static let providers: [String: CloudProvider] = ["openai": .openAI, "anthropic": .anthropic,
                                                            "gemini": .gemini]

    /// The brief's Outcome sentence (brief "Outcome").
    public static let outcomeSentence = "The AC needs servicing before summer, we're almost out of dishwasher pods, "
        + "and let's deep clean the balcony this weekend if it doesn't rain"

    public static func run(_ arguments: [String], io: ToolIO) -> Int32 {
        let provider: CloudProvider
        do throws(UsageError) {
            let parsed = try ParsedArguments(arguments, options: ["provider"], flags: ["outcome-sample", "help"])
            if parsed.flags.contains("help") { io.standardOutput(usage); return 0 }
            let name = try parsed.required("provider")
            guard let known = providers[name] else { throw UsageError("unknown provider: \(name)") }
            guard parsed.flags.contains("outcome-sample") else { throw UsageError("--outcome-sample is required") }
            provider = known
        } catch {
            io.standardError("tend-payload-dump: \(error.message)\n\(usage)")
            return EvalScoreCommand.exitUsage
        }
        let model = CloudModel.defaultModel(for: provider)
        let input = CloudPayloadInput(capture: outcomeSentence, roomNames: [], shortlistTitles: [])
        let body: Data
        do {
            body = try CloudPayloadBuilder.body(input, model: model)
        } catch {
            // Unreachable: the builder's member names are fixed and distinct.
            io.standardError("tend-payload-dump: the body could not be built\n")
            return EvalScoreCommand.exitRejected
        }
        let endpoint = CloudProviderTable.endpoint(for: provider)
        var target = endpoint.host + endpoint.path(for: model)
        if !endpoint.queryItems.isEmpty {
            target += "?" + endpoint.queryItems.map { $0.name + "=" + $0.value }.joined(separator: "&")
        }
        io.standardError("tend-payload-dump: POST \(target) (\(model.rawValue), \(body.count) bytes)\n")
        io.standardOutput(String(decoding: body, as: UTF8.self))
        return 0
    }
}
