// The route rule (ADR-0005 Decision 1; brief Definitions "Route", "Cloud model"; plan "Route matrix"). AC-M2-19,
// AC-M2-10. P-1, P-3.
//
// A pure function of three inputs: on-device availability, the user's preference and whether cloud is on (and for
// which provider). Whether cloud is on is decided from the stored consent and key by `ModelRouter.cloudStatus()`.

import Foundation

/// Whether the on-device language model can be used for this capture (plan route matrix, input A). The `TendAI`
/// adapter maps `SystemLanguageModel.Availability` and `supportsLocale` onto it (WI-M2-M2, owner-run Mac).
public enum OnDeviceAvailability: Hashable, Sendable {
    case available
    case unavailable(OnDeviceUnavailableReason)
}

/// The user's model preference (Settings, M3). The default is on device first (ADR-0005 Decision 1).
public enum RoutePreference: CaseIterable, Hashable, Sendable {
    /// Use the on-device model whenever it is available.
    case onDeviceFirst
    /// "Always use my cloud model". Ignored while cloud is off (T-12).
    case alwaysCloud
}

/// Whether cloud is on: the selected provider has both a consent record and a stored key (brief Definitions). Anything
/// else is off, which is the default.
public enum CloudStatus: Hashable, Sendable {
    case off
    case on(CloudProvider)
}

/// ADR-0005 Decision 1, written once.
public enum RouteRules {
    /// - On device first: the on-device model whenever it is available.
    /// - Cloud only when cloud is on **and** (the on-device model is unavailable, or the user chose "always cloud").
    /// - Otherwise no model (`none`): cloud off and the on-device model unavailable.
    /// An on-device error after this choice never changes the route: the pipeline holds one model (`RoutedModel`).
    public static func route(availability: OnDeviceAvailability, preference: RoutePreference,
                             cloud: CloudStatus) -> Route {
        switch (availability, cloud) {
        case (.available, .off):
            return .onDevice
        case let (.available, .on(provider)):
            return preference == .alwaysCloud ? .cloud(provider) : .onDevice
        case let (.unavailable, .on(provider)):
            return .cloud(provider)
        case (.unavailable, .off):
            return .none
        }
    }
}
