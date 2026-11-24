// The payload builder for the three providers (ADR-0005 Decision 3: "a pure, Foundation-only payload builder … It
// returns plain values: provider, path, header names, body bytes"; brief AC-M2-20; plan WI-M2-10). P-3.
//
// The builder is the only code that turns household data into request bytes, and its input type holds only the
// capture, the room names and the shortlist titles (`CloudPayloadInput`). Its output is deterministic: the same input,
// model and key give the same bytes on Linux and Darwin (canonical JSON, R-10).
//
// The user content: one text in the provider's user slot, the canonical JSON object
//   {"capture": <capture>, "existingTasks": [{"index": 1, "title": <title 1>}, …], "rooms": [<room name>, …]}
// so a capture, room name or title is always a JSON string value and can never change the structure around it. The
// index of a title is its shortlist rank (1…n), the number a model's `sameAsExisting` claim names (WI-M2-07).
//
// The builder enforces the shortlist cap itself (review R28-F3; Q12, ADR-0005 Decision 3, AC-M2-20 "n ≤ 10"): an input
// with more than `CloudPayloadInput.maximumShortlistTitles` titles is refused with a typed error and no bytes are made.
//
// Bodies (members in the canonical order the bytes have). Members marked (profile) come from the model's request
// profile (`CloudProviderTable.profile(for:)`, review R28-F7; PO WI-M2-10 ruling 7), never from a provider branch:
// - OpenAI `POST /v1/chat/completions`: `max_completion_tokens`, `messages` = [system: [{text: instructions,
//   type: text}], user: [{text: user content, type: text}]] (both text-part arrays, GR-5), `model`, (profile) `reasoning_effort`, `response_format` = json_schema
//   (`name`, (profile) schema member, `strict: true`), `store: false`, `stream: true`, (profile) `stream_options`,
//   (profile) `temperature`.
// - Anthropic `POST /v1/messages`: `max_tokens`, `messages` = [user: [{text, type: text}]], `model`, `stream: true`,
//   `system`: instructions, (profile) `temperature`, `tool_choice` = the one tool, `tools` = [{description,
//   (profile) schema member, name}] (structured output by one forced tool).
// - Gemini `POST /v1beta/models/<model>:streamGenerateContent?alt=sse`: `contents` = [user: parts [{text}]],
//   `generationConfig` = {`maxOutputTokens`, `responseMimeType: application/json`, (profile) schema member,
//   (profile) `temperature`, (profile) `thinkingConfig`}, `systemInstruction` = {parts [{text: instructions}]}.
// Pure: no I/O, no clock, no logging.

import Foundation

/// Why the builder made no request.
public enum CloudPayloadError: Error, Sendable, Equatable {
    /// The input holds more shortlist titles than a request may carry (Q12: at most 10).
    case tooManyShortlistTitles(count: Int)
    /// The canonical JSON writer refused the value (unreachable: the builder's member names are fixed and distinct).
    case json(CanonicalJSONError)
}

public enum CloudPayloadBuilder {

    /// The request for one capture to `model`'s provider, with `key` in the provider's auth header only.
    public static func request(_ input: CloudPayloadInput, model: CloudModel,
                               key: APIKey) throws(CloudPayloadError) -> CloudRequest {
        let endpoint = CloudProviderTable.endpoint(for: model.provider)
        let auth = CloudRequestHeader(name: endpoint.authHeaderName,
                                      content: .key(prefix: endpoint.authValuePrefix, key))
        let fixed = endpoint.fixedHeaders.map { CloudRequestHeader(name: $0.name, content: .text($0.value)) }
        return CloudRequest(provider: model.provider, model: model, method: "POST", host: endpoint.host,
                            path: endpoint.path(for: model), queryItems: endpoint.queryItems, headers: [auth] + fixed,
                            body: try body(input, model: model))
    }

    /// The canonical JSON body (it holds no key).
    public static func body(_ input: CloudPayloadInput, model: CloudModel) throws(CloudPayloadError) -> Data {
        try body(input, model: model, profile: model.requestProfile)
    }

    /// The body with an explicit profile (tests: a same-provider profile needs no builder change, review R28-F7).
    static func body(_ input: CloudPayloadInput, model: CloudModel,
                     profile: CloudRequestProfile) throws(CloudPayloadError) -> Data {
        let value = try bodyValue(input, model: model, profile: profile)
        do {
            return try CanonicalJSONWriter.data(value)
        } catch {
            throw .json(error)
        }
    }

    /// The user content text: the canonical JSON object of the three slots.
    public static func userContent(_ input: CloudPayloadInput) throws(CloudPayloadError) -> String {
        let count = input.shortlistTitles.count
        guard count <= CloudPayloadInput.maximumShortlistTitles else { throw .tooManyShortlistTitles(count: count) }
        do {
            return try CanonicalJSONWriter.string(.object([
                .init("capture", .string(input.capture)),
                .init("existingTasks", .array(input.shortlistTitles.enumerated().map { offset, title in
                    .object([.init("index", .integer(offset + 1)), .init("title", .string(title))])
                })),
                .init("rooms", .array(input.roomNames.map { .string($0) })),
            ]))
        } catch {
            throw .json(error)
        }
    }

    static func bodyValue(_ input: CloudPayloadInput, model: CloudModel,
                          profile: CloudRequestProfile) throws(CloudPayloadError) -> CanonicalJSON {
        let user = try userContent(input)
        let instructions = CanonicalJSON.string(CloudInstructions.text)
        let schema = CanonicalJSON.Member(profile.schemaMember, CloudOutputSchema.root(profile.schemaDialect))
        let maxTokens = CanonicalJSON.integer(CloudProviderTable.maxOutputTokens)
        let textPart: CanonicalJSON = .object([.init("type", .string("text")), .init("text", .string(user))])
        // OpenAI's system content is a text-part array like the user's (GR-5): no key path is both a leaf and a
        // container, so the device's key-path subset check sees a content that turned into a plain string.
        let instructionsPart: CanonicalJSON = .object([.init("type", .string("text")), .init("text", instructions)])
        let temperature: [CanonicalJSON.Member] = switch profile.sampling {
        case .temperatureZero: [.init("temperature", .integer(0))]
        case .providerDefault: []
        }
        switch model.provider {
        case .openAI:
            var reasoning: [CanonicalJSON.Member] = []
            if case let .openAIReasoningEffort(level) = profile.reasoning {
                reasoning = [.init("reasoning_effort", .string(level))]
            }
            let usage: [CanonicalJSON.Member] = switch profile.usage {
            case .openAIStreamOptionsIncludeUsage:
                [.init("stream_options", .object([.init("include_usage", .bool(true))]))]
            case .streamedByDefault: []
            }
            return .object([
                .init("model", .string(model.rawValue)),
                .init("messages", .array([
                    .object([.init("role", .string("system")), .init("content", .array([instructionsPart]))]),
                    .object([.init("role", .string("user")), .init("content", .array([textPart]))]),
                ])),
                .init("response_format", .object([
                    .init("type", .string("json_schema")),
                    .init("json_schema", .object([
                        .init("name", .string(CloudInstructions.openAISchemaName)),
                        .init("strict", .bool(true)),
                        schema,
                    ])),
                ])),
                .init("stream", .bool(true)),
                .init("store", .bool(false)),
                .init("max_completion_tokens", maxTokens),
            ] + usage + reasoning + temperature)
        case .anthropic:
            return .object([
                .init("model", .string(model.rawValue)),
                .init("system", instructions),
                .init("messages", .array([
                    .object([.init("role", .string("user")), .init("content", .array([textPart]))]),
                ])),
                .init("tools", .array([
                    .object([
                        .init("name", .string(CloudInstructions.anthropicToolName)),
                        .init("description", .string(CloudInstructions.anthropicToolDescription)),
                        schema,
                    ]),
                ])),
                .init("tool_choice", .object([
                    .init("type", .string("tool")), .init("name", .string(CloudInstructions.anthropicToolName)),
                ])),
                .init("stream", .bool(true)),
                .init("max_tokens", maxTokens),
            ] + temperature)
        case .gemini:
            let thinking: [CanonicalJSON.Member] = switch profile.reasoning {
            case let .geminiThinkingLevel(level):
                [.init("thinkingConfig", .object([.init("thinkingLevel", .string(level))]))]
            case let .geminiThinkingBudget(budget):
                [.init("thinkingConfig", .object([.init("thinkingBudget", .integer(budget))]))]
            case .noMember, .openAIReasoningEffort: []
            }
            return .object([
                .init("systemInstruction", .object([.init("parts", .array([.object([.init("text", instructions)])]))])),
                .init("contents", .array([
                    .object([
                        .init("role", .string("user")),
                        .init("parts", .array([.object([.init("text", .string(user))])])),
                    ]),
                ])),
                .init("generationConfig", .object([
                    .init("responseMimeType", .string("application/json")),
                    schema,
                    .init("maxOutputTokens", maxTokens),
                ] + thinking + temperature)),
            ])
        }
    }
}
