// The on-device model source for routing (WI-M2-M2; `OnDeviceModelSource`; AC-M2-10; ADR-0005 Decision 1(a)). P-1.
//
// `availability()` maps `SystemLanguageModel.default.availability` and `supportsLocale` to the neutral value that
// `RouteRules` reads. `model(household:)` gives the capture's model, whose Tool reads exactly that household.
// `prewarm(household:)` prepares and prewarms the session when capture starts (the user taps before speaking, Q4).

import Foundation
import FoundationModels
import TendCore
import TendIngestion

public struct FoundationModelsOnDeviceSource: OnDeviceModelSource {
    /// The framework's availability and whether the model supports the capture locale.
    let readAvailability: @Sendable () -> (availability: SystemLanguageModel.Availability, supportsLocale: Bool)
    let makeGeneration: @Sendable (Household) -> any OnDeviceGeneration
    let prepared = PreparedGenerations()

    /// - Parameter locale: the language of the captures (the device locale in the app).
    public init(locale: Locale = .current) {
        self.init(
            readAvailability: {
                let model = SystemLanguageModel.default
                return (model.availability, model.supportsLocale(locale))
            },
            makeGeneration: { FoundationModelsGeneration(household: $0) }
        )
    }

    init(readAvailability: @escaping @Sendable () -> (availability: SystemLanguageModel.Availability,
                                                     supportsLocale: Bool),
         makeGeneration: @escaping @Sendable (Household) -> any OnDeviceGeneration) {
        self.readAvailability = readAvailability
        self.makeGeneration = makeGeneration
    }

    public func availability() -> OnDeviceAvailability {
        let read = readAvailability()
        return OnDeviceAvailabilityMapping.neutral(read.availability, supportsLocale: read.supportsLocale)
    }

    public func model(household: Household) -> any IngestionModel {
        OnDeviceIngestionModel(household: household, prepared: prepared, makeGeneration: makeGeneration)
    }

    /// Prepares the next capture's session for `household` and prewarms it. Call it when capture starts; the next
    /// `model(household:)` with an equal household uses it.
    public func prewarm(household: Household) async {
        let generation = makeGeneration(household)
        generation.prewarm()
        await prepared.store(generation, for: household)
    }
}
