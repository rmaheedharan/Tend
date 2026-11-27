// The on-device `IngestionModel`: one `LanguageModelSession` per capture, streaming the `@Generable` answer
// (WI-M2-M2; AC-M2-05, AC-M2-07, AC-M2-10; `IngestionModel` adapter contract items 1-4). FR-A1, P-1, P-4.
//
// - **Contract 1.** The stream finishes normally, or throws a `ModelStopReason` (`OnDeviceStopMapping`).
// - **Contract 2.** It keeps no reference to the stream it returns.
// - **Contract 3.** Its `onTermination` cancels the generation task, which ends `streamResponse`. A stream created
//   inside an already cancelled task starts no generation and finishes at once.
// - **Contract 4.** Every snapshot carries the Tool's queries so far; after the answer ends normally, one more snapshot
//   carries the final answer with every property finished and the final queries.
// - The capture and the room names go in the prompt as JSON data, never in the instructions.
// - Nothing is persisted or logged (P-4): the prompt and the answer live only in memory for the capture.

import Foundation
import FoundationModels
import TendCore
import TendIngestion

/// One parse's model work: its duplicate-lookup recorder and its stream of answers.
protocol OnDeviceGeneration: Sendable {
    /// The recorder behind this parse's Tool.
    var recorder: DuplicateLookupRecorder { get }
    /// Loads the model and the instructions before the capture is ready (Q4).
    func prewarm()
    /// The answer so far, once per model step. Ends normally or throws the framework's error. Its termination ends
    /// the model's work.
    func answers(prompt: String) -> AsyncThrowingStream<OnDeviceOutput.PartiallyGenerated, any Error>
}

/// The real generation: a fresh `LanguageModelSession` with the fixed instructions and the duplicate `Tool`.
final class FoundationModelsGeneration: OnDeviceGeneration {
    let recorder: DuplicateLookupRecorder
    private let session: LanguageModelSession

    init(household: Household) {
        let recorder = DuplicateLookupRecorder(household: household)
        self.recorder = recorder
        session = LanguageModelSession(model: .default, tools: [DuplicateLookupTool(recorder: recorder)],
                                       instructions: OnDeviceInstructions.text)
    }

    func prewarm() {
        session.prewarm()
    }

    func answers(prompt: String) -> AsyncThrowingStream<OnDeviceOutput.PartiallyGenerated, any Error> {
        let session = session
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // Greedy sampling: the same capture gives the same answer (the on-device counterpart of Q18
                    // condition 4).
                    let responses = session.streamResponse(to: prompt, generating: OnDeviceOutput.self,
                                                           options: GenerationOptions(samplingMode: .greedy))
                    for try await response in responses {
                        continuation.yield(response.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// The on-device model for one capture's household.
struct OnDeviceIngestionModel: IngestionModel {
    let household: Household
    /// Hands out a generation prepared (prewarmed) for this household, if there is one.
    let prepared: PreparedGenerations
    /// Makes a fresh generation for a household (the real session, or a script in the tests).
    let makeGeneration: @Sendable (Household) -> any OnDeviceGeneration

    func snapshots(for request: IngestionRequest) -> AsyncThrowingStream<IngestionSnapshot, any Error> {
        let household = household
        let prepared = prepared
        let makeGeneration = makeGeneration
        // The build closure runs at once, in the caller's task.
        return AsyncThrowingStream { continuation in
            // Contract 3: created inside a cancelled task (a cancel just before the parse) starts nothing.
            guard !Task.isCancelled else {
                continuation.finish()
                return
            }
            let task = Task {
                let generation = await prepared.take(for: household) ?? makeGeneration(household)
                guard let prompt = Self.prompt(for: request) else {
                    continuation.finish(throwing: ModelStopReason.otherModelError)
                    return
                }
                var last: OnDeviceOutput.PartiallyGenerated?
                var carriedQueries: [String] = []
                do {
                    for try await answer in generation.answers(prompt: prompt) {
                        let queries = await generation.recorder.queries
                        continuation.yield(OnDeviceSnapshotMapping.snapshot(answer, isFinal: false,
                                                                            lookupQueries: queries))
                        last = answer
                        carriedQueries = queries
                    }
                    if Task.isCancelled {
                        continuation.finish()
                        return
                    }
                    let queries = await generation.recorder.queries
                    if let last {
                        continuation.yield(OnDeviceSnapshotMapping.snapshot(last, isFinal: true,
                                                                            lookupQueries: queries))
                    } else if queries != carriedQueries {
                        continuation.yield(IngestionSnapshot(items: [], lookupQueries: queries))
                    }
                    continuation.finish()
                } catch {
                    if Task.isCancelled {
                        // A parse the consumer cancelled is not a model stop (the pipeline reports `cancelled`). A
                        // `CancellationError` the framework throws while this parse is not cancelled is a stop like
                        // any other (`otherModelError`: interrupted after a draft, noModel before one; review PR #41 m1).
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: OnDeviceStopMapping.reason(for: error))
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The prompt: the capture and the room names as a JSON object (data, never instructions).
    static func prompt(for request: IngestionRequest) -> String? {
        struct PromptData: Encodable {
            let capture: String
            let rooms: [String]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(PromptData(capture: request.input, rooms: request.roomNames)) else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }
}

/// At most one generation prepared ahead of a capture, for the household it was prepared with (Q4: the session may
/// be prewarmed when capture starts). A capture for another household gets a fresh generation, so the Tool always
/// reads the capture's own household.
actor PreparedGenerations {
    private var slot: (household: Household, generation: any OnDeviceGeneration)?

    func store(_ generation: any OnDeviceGeneration, for household: Household) {
        slot = (household, generation)
    }

    /// The prepared generation, once, if it was prepared for `household`.
    func take(for household: Household) -> (any OnDeviceGeneration)? {
        guard let slot, slot.household == household else { return nil }
        self.slot = nil
        return slot.generation
    }
}
