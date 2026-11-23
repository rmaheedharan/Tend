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
// Bodies (members shown in the canonical order the bytes have):
// - OpenAI `POST /v1/chat/completions`: `max_completion_tokens`, `messages` = [system: instructions,
//   user: [{text: user content, type: text}]], `model`, `response_format` = json_schema (`name`, `schema`,
//   `strict: true`), `store: false`, `stream: true`, `temperature: 0`.
// - Anthropic `POST /v1/messages`: `max_tokens`, `messages` = [user: [{text, type: text}]], `model`, `stream: true`,
//   `system`: instructions, `temperature: 0`, `tool_choice` = the one tool, `tools` = [{description, input_schema,
//   name}] (structured output by one forced tool).
// - Gemini `POST /v1beta/models/<model>:streamGenerateContent?alt=sse`: `contents` = [user: parts [{text}]],
//   `generationConfig` = {`maxOutputTokens`, `responseMimeType: application/json`, `responseSchema`,
//   `temperature: 0`, `thinkingConfig: {thinkingBudget: 0}`}, `systemInstruction` = {parts [{text: instructions}]}.
// Pure: no I/O, no clock, no logging.

import Foundation

public enum CloudPayloadBuilder {

    /// The request for one capture to `model`'s provider, with `key` in the provider's auth header only.
    public static func request(_ input: CloudPayloadInput, model: CloudModel,
                               key: APIKey) throws(CanonicalJSONError) -> CloudRequest {
        let endpoint = CloudProviderTable.endpoint(for: model.provider)
        let auth = CloudRequestHeader(name: endpoint.authHeaderName,
                                      content: .key(prefix: endpoint.authValuePrefix, key))
        let fixed = endpoint.fixedHeaders.map { CloudRequestHeader(name: $0.name, content: .text($0.value)) }
        return CloudRequest(provider: model.provider, model: model, method: "POST", host: endpoint.host,
                            path: endpoint.path(for: model), queryItems: endpoint.queryItems, headers: [auth] + fixed,
                            body: try body(input, model: model))
    }

    /// The canonical JSON body (it holds no key).
    public static func body(_ input: CloudPayloadInput, model: CloudModel) throws(CanonicalJSONError) -> Data {
        try CanonicalJSONWriter.data(bodyValue(input, model: model))
    }

    /// The user content text: the canonical JSON object of the three slots.
    public static func userContent(_ input: CloudPayloadInput) throws(CanonicalJSONError) -> String {
        try CanonicalJSONWriter.string(.object([
            .init("capture", .string(input.capture)),
            .init("existingTasks", .array(input.shortlistTitles.enumerated().map { offset, title in
                .object([.init("index", .integer(offset + 1)), .init("title", .string(title))])
            })),
            .init("rooms", .array(input.roomNames.map { .string($0) })),
        ]))
    }

    static func bodyValue(_ input: CloudPayloadInput, model: CloudModel) throws(CanonicalJSONError) -> CanonicalJSON {
        let user = try userContent(input)
        let instructions = CanonicalJSON.string(CloudInstructions.text)
        let schema = CloudOutputSchema.root(CloudSchemaDialect(model.provider))
        let maxTokens = CanonicalJSON.integer(CloudProviderTable.maxOutputTokens)
        let textPart: CanonicalJSON = .object([.init("type", .string("text")), .init("text", .string(user))])
        switch model.provider {
        case .openAI:
            return .object([
                .init("model", .string(model.rawValue)),
                .init("messages", .array([
                    .object([.init("role", .string("system")), .init("content", instructions)]),
                    .object([.init("role", .string("user")), .init("content", .array([textPart]))]),
                ])),
                .init("response_format", .object([
                    .init("type", .string("json_schema")),
                    .init("json_schema", .object([
                        .init("name", .string(CloudInstructions.openAISchemaName)),
                        .init("strict", .bool(true)),
                        .init("schema", schema),
                    ])),
                ])),
                .init("stream", .bool(true)),
                .init("store", .bool(false)),
                .init("temperature", .integer(0)),
                .init("max_completion_tokens", maxTokens),
            ])
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
                        .init("input_schema", schema),
                    ]),
                ])),
                .init("tool_choice", .object([
                    .init("type", .string("tool")), .init("name", .string(CloudInstructions.anthropicToolName)),
                ])),
                .init("stream", .bool(true)),
                .init("temperature", .integer(0)),
                .init("max_tokens", maxTokens),
            ])
        case .gemini:
            return .object([
                .init("systemInstruction", .object([.init("parts", .array([.object([.init("text", instructions)])]))])),
                .init("contents", .array([
                    .object([
                        .init("role", .string("user")),
                        .init("parts", .array([.object([.init("text", .string(user))])])),
                    ]),
                ])),
                .init("generationConfig", .object([
                    .init("temperature", .integer(0)),
                    .init("responseMimeType", .string("application/json")),
                    .init("responseSchema", schema),
                    .init("thinkingConfig", .object([.init("thinkingBudget", .integer(0))])),
                    .init("maxOutputTokens", maxTokens),
                ])),
            ])
        }
    }
}
