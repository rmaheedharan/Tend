// The provider table (plan WI-M2-10; ADR-0005 Decisions 4, 5 and 6; brief AC-M2-20, Q18). P-2, P-3.
//
// This is the one file in which the three bare hosts appear (brief AC-M2-09 Rule 4 "Where they may appear"; review
// R1-F6: the scan allows bare hosts in this file only). `https://` never appears here: the transport in `TendAI` builds
// the URL with `URLComponents` from the host, path and query items (WI-M2-M4).
//
// Curated models (Q18; PO WI-M2-10 ruling 7, the final M2 list after live checks L1 and L1b, 2026-11-23). There is no
// free-text model ID: a release changes this list. The model is the unit of configuration (review R28-F7): each
// `CloudModel` has a fixed request profile below (sampling, reasoning member, usage member, schema dialect and schema
// member), and the builder reads the profile, so a same-provider model swap is a change to this file only. The list may
// hold fallback models after the default, but only `defaultModel(for:)` is used; a switch needs a PO ruling (ruling 7).
// The IDs and profile values come from PO ruling 7 and the L1b notes; this container has no web access, so nothing here
// was read from the providers' current documentation (plan R-6). Live check L2a (owner, real recordings) confirms
// them on the wire before the WI-M2-16 golden review.
//
// Request-level retention options (ADR-0005 Decision 4; AC-M2-20 "Opt-outs"), set by `CloudPayloadBuilder`:
// - OpenAI: `store: false` (no stored completion).
// - Anthropic and Gemini: none at request level; Gemini training use depends on the key's tier (Q17).
// Every fixed member passes PO ruling 3's six-part test: a constant, no household or device data, a protocol member or
// schema keyword, nothing that widens the provider's reach, listed as `fixed` in the allowed lists, and no 600…729.
// Pure values: no I/O, no clock, no logging.

import Foundation

/// The curated models (Q18). The raw value is the ID sent to the provider. Case names are neutral, so a model swap
/// changes the raw value and the profile, not the callers.
public enum CloudModel: String, CaseIterable, Hashable, Sendable {
    /// The OpenAI default (ruling 7: the provider lists only this snapshot name; drift check on the served `model`).
    case openAIDefault = "gpt-6-luna"
    /// The Anthropic default (dated snapshot ID).
    case anthropicDefault = "claude-haiku-4-5-20251001"
    /// The Gemini default (stable version ID; drift check on the served `modelVersion`).
    case geminiDefault = "gemini-3.5-flash-lite"

    public var provider: CloudProvider {
        switch self {
        case .openAIDefault: .openAI
        case .anthropicDefault: .anthropic
        case .geminiDefault: .gemini
        }
    }

    /// The fixed request profile of this model (review R28-F7).
    public var requestProfile: CloudRequestProfile { CloudProviderTable.profile(for: self) }

    /// The curated models of `provider`: the default first, then any listed fallback (never used without a PO ruling).
    public static func curated(for provider: CloudProvider) -> [CloudModel] {
        let primary = defaultModel(for: provider)
        return [primary] + allCases.filter { $0.provider == provider && $0 != primary }
    }

    /// The model used for `provider` (Q18; PO WI-M2-10 ruling 7).
    public static func defaultModel(for provider: CloudProvider) -> CloudModel {
        switch provider {
        case .openAI: .openAIDefault
        case .anthropic: .anthropicDefault
        case .gemini: .geminiDefault
        }
    }
}

/// The model-dependent members of a request (review R28-F7; Q18 revised conditions 4 and 5, PO WI-M2-10 ruling 7).
public struct CloudRequestProfile: Hashable, Sendable {

    /// Q18 condition 4 (revised): `temperature: 0` where the model accepts it, otherwise no `temperature` member.
    public enum Sampling: Hashable, Sendable {
        case temperatureZero
        case providerDefault
    }

    /// Q18 condition 5 (revised): the lowest documented reasoning or thinking level, set explicitly.
    public enum Reasoning: Hashable, Sendable {
        /// No member: the model does not think unless asked (Anthropic without a `thinking` member).
        case noMember
        /// OpenAI top-level `reasoning_effort`.
        case openAIReasoningEffort(String)
        /// Gemini `generationConfig.thinkingConfig.thinkingLevel`.
        case geminiThinkingLevel(String)
        /// Gemini `generationConfig.thinkingConfig.thinkingBudget`.
        case geminiThinkingBudget(Int)
    }

    /// Q18 condition 5 (revised): the member, if any, the provider needs to stream usage (reasoning-token counts).
    public enum UsageReport: Hashable, Sendable {
        /// The provider streams usage with no extra member (Anthropic `message_delta`, Gemini `usageMetadata`).
        case streamedByDefault
        /// OpenAI `stream_options: {"include_usage": true}`.
        case openAIStreamOptionsIncludeUsage
    }

    public let sampling: Sampling
    public let reasoning: Reasoning
    public let usage: UsageReport
    /// How the output schema writes a member that may be null.
    public let schemaDialect: CloudSchemaDialect
    /// The member that holds the output schema: OpenAI `json_schema.<member>`, Anthropic `tools[0].<member>`, Gemini
    /// `generationConfig.<member>`.
    public let schemaMember: String

    public init(sampling: Sampling, reasoning: Reasoning, usage: UsageReport, schemaDialect: CloudSchemaDialect,
                schemaMember: String) {
        self.sampling = sampling
        self.reasoning = reasoning
        self.usage = usage
        self.schemaDialect = schemaDialect
        self.schemaMember = schemaMember
    }

    /// Whether every member of this profile has a place in `provider`'s body.
    public func fits(_ provider: CloudProvider) -> Bool {
        let reasoningFits = switch reasoning {
        case .noMember: true
        case .openAIReasoningEffort: provider == .openAI
        case .geminiThinkingLevel, .geminiThinkingBudget: provider == .gemini
        }
        let usageFits = usage == .streamedByDefault || provider == .openAI
        return reasoningFits && usageFits && !schemaMember.isEmpty
    }
}

/// One fixed header (name and value).
public struct CloudFixedHeader: Hashable, Sendable {
    public let name: String
    public let value: String
}

/// Where and how one provider is called.
public struct CloudProviderEndpoint: Hashable, Sendable {
    public let provider: CloudProvider
    /// The bare host (no scheme, no port); HTTPS is the transport's rule (ADR-0005 Decision 6).
    public let host: String
    /// The header that carries the key, and the text before the key in its value.
    public let authHeaderName: String
    public let authValuePrefix: String
    /// The other headers, in order, after the auth header.
    public let fixedHeaders: [CloudFixedHeader]
    /// The query items (Gemini: `alt=sse`). The key is never a query item (AC-M2-20 "Key placement").
    public let queryItems: [CloudQueryItem]

    /// The request path for `model`.
    public func path(for model: CloudModel) -> String {
        switch provider {
        case .openAI: "/v1/chat/completions"
        case .anthropic: "/v1/messages"
        case .gemini: "/v1beta/models/" + model.rawValue + ":streamGenerateContent"
        }
    }
}

public enum CloudProviderTable {

    /// The three hosts of ADR-0005 Decision 6, in `CloudProvider` order.
    public static let hosts: [String] = CloudProvider.allCases.map { endpoint(for: $0).host }

    /// The `Content-Type` of every request body.
    static let jsonContentType = CloudFixedHeader(name: "Content-Type", value: "application/json")

    /// The two client headers every request sets explicitly, after the provider's headers, so the device's defaults
    /// (the person's preferred languages; the app build, CFNetwork and Darwin versions) are never sent (PO WI-M2-10
    /// ruling 4; WI-M2-16 ruling 10, GR-3; brief AC-M2-22 Headers). Constants, the same for every user and request.
    static let clientHeaders = [CloudFixedHeader(name: "User-Agent", value: "Tend"),
                                CloudFixedHeader(name: "Accept-Language", value: "en-US")]

    /// The Anthropic API version header value.
    static let anthropicVersion = "2023-06-01"

    /// The fixed output cap of every request (N-3: its digits hold no 600…729).
    static let maxOutputTokens = 4096

    /// The request profile of each curated model (PO WI-M2-10 ruling 7, "Exact fixed request members per provider").
    public static func profile(for model: CloudModel) -> CloudRequestProfile {
        switch model {
        case .openAIDefault:
            // No `temperature` (not documented for this model); `reasoning_effort: "none"`, the lowest documented
            // level; usage streamed only with `stream_options.include_usage`.
            CloudRequestProfile(sampling: .providerDefault, reasoning: .openAIReasoningEffort("none"),
                                usage: .openAIStreamOptionsIncludeUsage, schemaDialect: .jsonSchemaNullAnyOf,
                                schemaMember: "schema")
        case .anthropicDefault:
            // `temperature: 0`; no `thinking` member, so the model does not think (Q18 conditions as first written).
            CloudRequestProfile(sampling: .temperatureZero, reasoning: .noMember, usage: .streamedByDefault,
                                schemaDialect: .jsonSchemaNullAnyOf, schemaMember: "input_schema")
        case .geminiDefault:
            // No `temperature`; `thinkingLevel: "minimal"`, the lowest documented level. The JSON-Schema member name
            // `responseJsonSchema` is from the L1b notes (the Go SDK's `ResponseJsonSchema`), not quoted from the REST
            // reference: live check L2a confirms it (dev-notes WI-M2-10 round 2).
            CloudRequestProfile(sampling: .providerDefault, reasoning: .geminiThinkingLevel("minimal"),
                                usage: .streamedByDefault, schemaDialect: .jsonSchemaNullTypeArray,
                                schemaMember: "responseJsonSchema")
        }
    }

    public static func endpoint(for provider: CloudProvider) -> CloudProviderEndpoint {
        switch provider {
        case .openAI:
            CloudProviderEndpoint(provider: .openAI, host: "api.openai.com", authHeaderName: "Authorization",
                                  authValuePrefix: "Bearer ", fixedHeaders: [jsonContentType] + clientHeaders,
                                  queryItems: [])
        case .anthropic:
            CloudProviderEndpoint(provider: .anthropic, host: "api.anthropic.com", authHeaderName: "x-api-key",
                                  authValuePrefix: "",
                                  fixedHeaders: [CloudFixedHeader(name: "anthropic-version", value: anthropicVersion),
                                                 jsonContentType] + clientHeaders,
                                  queryItems: [])
        case .gemini:
            CloudProviderEndpoint(provider: .gemini, host: "generativelanguage.googleapis.com",
                                  authHeaderName: "x-goog-api-key", authValuePrefix: "",
                                  fixedHeaders: [jsonContentType] + clientHeaders,
                                  queryItems: [CloudQueryItem(name: "alt", value: "sse")])
        }
    }
}
