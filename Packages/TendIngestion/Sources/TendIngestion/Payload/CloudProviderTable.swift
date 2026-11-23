// The provider table (plan WI-M2-10; ADR-0005 Decisions 4, 5 and 6; brief AC-M2-20, Q18). P-2, P-3.
//
// This is the one file in which the three bare hosts appear (brief AC-M2-09 Rule 4 "Where they may appear"; review
// R1-F6: the scan allows bare hosts in this file only). `https://` never appears here: the transport in `TendAI` builds
// the URL with `URLComponents` from the host, path and query items (WI-M2-M4).
//
// Curated models (Q18, approved by the PO 2026-11-21 with five conditions). The ID sent is a pinned snapshot ID, never
// a moving alias. There is no free-text model ID: a release changes this list. The IDs were written from the plan and
// the Developer's knowledge; they were not checked against the providers' current documentation in this container
// (no web access). WI-M2-M6 re-checks all five conditions before the real recordings (plan R-6; dev-notes WI-M2-10
// open questions).
//
// Request-level options per provider (ADR-0005 Decision 4; AC-M2-20 "Opt-outs"), set by `CloudPayloadBuilder`:
// - OpenAI: `store: false` (no stored completion). No other retention or training option at request level.
// - Anthropic: none offered at request level.
// - Gemini: none offered at request level; training use depends on the key's tier (Q17).
// Sampling and reasoning (Q18 conditions 4 and 5): `temperature: 0` for all three; Gemini `thinkingBudget: 0`;
// Anthropic sends no `thinking` member, so extended thinking stays off; `gpt-4.1-mini` is not a reasoning model.
// Pure values: no I/O, no clock, no logging.

import Foundation

/// The curated models (Q18). The raw value is the pinned ID sent to the provider.
public enum CloudModel: String, CaseIterable, Hashable, Sendable {
    /// OpenAI GPT-4.1 mini, snapshot of 2025-04-14.
    case gpt41Mini = "gpt-4.1-mini-2025-04-14"
    /// Anthropic Claude Haiku 4.5, snapshot of 2025-10-01.
    case claudeHaiku45 = "claude-haiku-4-5-20251001"
    /// Google Gemini 2.5 Flash, stable version ID (Google gives no dated snapshot for it; open question R-6).
    case gemini25Flash = "gemini-2.5-flash"

    public var provider: CloudProvider {
        switch self {
        case .gpt41Mini: .openAI
        case .claudeHaiku45: .anthropic
        case .gemini25Flash: .gemini
        }
    }

    /// The curated models of `provider`, default first.
    public static func curated(for provider: CloudProvider) -> [CloudModel] {
        allCases.filter { $0.provider == provider }
    }

    /// The default model of `provider` (Q18).
    public static func defaultModel(for provider: CloudProvider) -> CloudModel {
        switch provider {
        case .openAI: .gpt41Mini
        case .anthropic: .claudeHaiku45
        case .gemini: .gemini25Flash
        }
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

    /// The Anthropic API version header value.
    static let anthropicVersion = "2023-06-01"

    /// The fixed output cap of every request (N-3: its digits hold no 600…729).
    static let maxOutputTokens = 4096

    public static func endpoint(for provider: CloudProvider) -> CloudProviderEndpoint {
        switch provider {
        case .openAI:
            CloudProviderEndpoint(provider: .openAI, host: "api.openai.com", authHeaderName: "Authorization",
                                  authValuePrefix: "Bearer ", fixedHeaders: [jsonContentType], queryItems: [])
        case .anthropic:
            CloudProviderEndpoint(provider: .anthropic, host: "api.anthropic.com", authHeaderName: "x-api-key",
                                  authValuePrefix: "",
                                  fixedHeaders: [CloudFixedHeader(name: "anthropic-version", value: anthropicVersion),
                                                 jsonContentType],
                                  queryItems: [])
        case .gemini:
            CloudProviderEndpoint(provider: .gemini, host: "generativelanguage.googleapis.com",
                                  authHeaderName: "x-goog-api-key", authValuePrefix: "",
                                  fixedHeaders: [jsonContentType],
                                  queryItems: [CloudQueryItem(name: "alt", value: "sse")])
        }
    }
}
