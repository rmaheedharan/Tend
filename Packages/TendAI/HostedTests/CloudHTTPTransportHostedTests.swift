// The HTTPS cloud transport over a `URLProtocol` stub, in the iOS 26.5 Simulator host (WI-M2-M4; brief AC-M2-22,
// AC-M2-23 adapter half; `CloudTransport` contract points 1-5; plan B5). P-2, P-3, P-4.
// The stub is installed only through the transport's test hook (`adjust`), so the source never names `URLProtocol`.

import Foundation
import Testing
@testable import TendAI
@testable import TendIngestion

/// What the stub does for one test, and what it saw. Keyed by a per-test header value, so tests can run in parallel.
final class StubBook: @unchecked Sendable {
    // @unchecked Sendable: every access goes through `lock`. Test target only.
    static let shared = StubBook()
    private let lock = NSLock()
    private var plans: [String: StubPlan] = [:]
    private var seen: [String: [URLRequest]] = [:]
    private var bodies: [String: [Data]] = [:]

    func set(_ plan: StubPlan, for id: String) { lock.withLock { plans[id] = plan } }
    func plan(_ id: String) -> StubPlan? { lock.withLock { plans[id] } }
    func record(_ request: URLRequest, body: Data, id: String) {
        lock.withLock { seen[id, default: []].append(request); bodies[id, default: []].append(body) }
    }
    func requests(_ id: String) -> [URLRequest] { lock.withLock { seen[id] ?? [] } }
    func sentBodies(_ id: String) -> [Data] { lock.withLock { bodies[id] ?? [] } }
}

enum StubPlan: Sendable {
    /// Status, headers and body chunks (sent in order).
    case respond(status: Int, headers: [String: String], chunks: [Data])
    /// A transport error.
    case fail(URLError.Code)
    /// A redirect to `location`.
    case redirect(location: String)
    /// Headers, then never anything more.
    case silentAfterHeaders
    /// Nothing at all.
    case silent
}

final class StubProtocol: URLProtocol, @unchecked Sendable {
    // @unchecked Sendable: URLProtocol is used on the loading thread only. Test target only.
    static let idHeader = "X-Test-ID"

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let id = request.value(forHTTPHeaderField: Self.idHeader) ?? ""
        StubBook.shared.record(request, body: Self.body(of: request), id: id)
        guard let url = request.url, let plan = StubBook.shared.plan(id) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        switch plan {
        case let .respond(status, headers, chunks):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
            if let response { client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
            for chunk in chunks { client?.urlProtocol(self, didLoad: chunk) }
            client?.urlProtocolDidFinishLoading(self)
        case let .fail(code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case let .redirect(location):
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1",
                                           headerFields: ["Location": location])
            var next = request
            next.url = URL(string: location, relativeTo: url)
            if let response {
                // Offer the redirect; when the session refuses it, the redirect response is the final response (as
                // the HTTP loader does). If it were followed, a new load of `next` would reach this stub and be seen.
                client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocolDidFinishLoading(self)
            }
        case .silentAfterHeaders:
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])
            if let response { client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
        case .silent:
            break
        }
    }

    override func stopLoading() {}

    static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(contentsOf: buffer[0..<read])
        }
        return data
    }
}

enum TransportFixtures {
    static let key = APIKey("sk-test-transport-0123456789")

    static func request(_ provider: CloudProvider) throws -> CloudRequest {
        try CloudPayloadBuilder.request(CloudPayloadInput(capture: "buy pods", roomNames: ["Kitchen"],
                                                          shortlistTitles: []),
                                        model: CloudModel.defaultModel(for: provider), key: key)
    }

    /// The same request with one field changed (tests of the refusals).
    static func altered(_ base: CloudRequest, host: String? = nil, extraHeader: CloudRequestHeader? = nil,
                        id: String) -> CloudRequest {
        CloudRequest(provider: base.provider, model: base.model, method: base.method, host: host ?? base.host,
                     path: base.path, queryItems: base.queryItems,
                     headers: base.headers + [CloudRequestHeader(name: StubProtocol.idHeader, content: .text(id))]
                        + (extraHeader.map { [$0] } ?? []),
                     body: base.body)
    }

    static func transport() -> CloudHTTPTransport {
        CloudHTTPTransport { configuration in configuration.protocolClasses = [StubProtocol.self] }
    }

    static let timeouts = CloudAttemptTimeouts(resource: 10.0, request: 4.0)

    /// Runs one attempt; returns the bytes and how it ended.
    static func send(_ request: CloudRequest, plan: StubPlan, id: String,
                     timeouts: CloudAttemptTimeouts = timeouts) async -> (chunks: [[UInt8]], end: (any Error)?) {
        StubBook.shared.set(plan, for: id)
        var chunks: [[UInt8]] = []
        do {
            for try await chunk in transport().send(request, timeouts: timeouts) { chunks.append(chunk) }
            return (chunks, nil)
        } catch {
            return (chunks, error)
        }
    }

    static func newID() -> String { UUID().uuidString }
}

@Suite("Cloud HTTPS transport (WI-M2-M4; AC-M2-22, AC-M2-23)")
struct CloudHTTPTransportHostedTests {
    typealias F = TransportFixtures

    @Test("AC-M2-22: each attempt uses an ephemeral configuration with no cookies, cache or credentials, and its timeouts")
    func configuration() {
        let configuration = CloudHTTPTransport.configuration(CloudAttemptTimeouts(resource: 7.5, request: 3.25))
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.urlCache == nil)
        #expect(configuration.urlCredentialStorage == nil)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.httpCookieAcceptPolicy == .never)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
        #expect(configuration.timeoutIntervalForResource == 7.5)
        #expect(configuration.timeoutIntervalForRequest == 3.25)
        #expect(configuration.httpAdditionalHeaders == nil)
    }

    @Test("AC-M2-22: a 2xx body arrives in order, in chunks cut at line ends and never one byte each",
          arguments: CloudProvider.allCases)
    func body(provider: CloudProvider) async throws {
        let id = F.newID()
        let request = F.altered(try F.request(provider), id: id)
        let lines = (1...300).map { "data: {\"n\":\($0)}\n\n" }.joined()
        let payload = Data(lines.utf8) + Data(repeating: 0x41, count: 9_000)
        let (chunks, end) = await F.send(request, plan: .respond(status: 200, headers: [:],
                                                                 chunks: [payload.prefix(5_000), payload.dropFirst(5_000)]),
                                         id: id)
        #expect(end == nil)
        #expect(Data(chunks.joined()) == payload)
        #expect(chunks.allSatisfy { $0.count <= CloudHTTPTransport.chunkLimit })
        // Whole server-sent events (cut at each blank line) or 4 KiB pieces, never single bytes (review R29-N2).
        #expect(chunks.allSatisfy { $0.count > 1 })
        #expect(chunks.count >= 300)
        // HTTPS to the provider's host and path, the builder's body, one request.
        let sent = StubBook.shared.requests(id)
        #expect(sent.count == 1)
        #expect(sent.first?.url?.scheme == "https")
        #expect(sent.first?.url?.host == request.host)
        #expect(sent.first?.url?.path == request.path)
        #expect(sent.first?.httpMethod == "POST")
        #expect(StubBook.shared.sentBodies(id).first == request.body)
        if provider == .gemini { #expect(sent.first?.url?.query == "alt=sse") }
    }

    @Test("AC-M2-22 Headers: User-Agent: Tend and Accept-Language: en-US are set explicitly; only the builder's headers are sent",
          arguments: CloudProvider.allCases)
    func headers(provider: CloudProvider) async throws {
        let id = F.newID()
        let request = F.altered(try F.request(provider), id: id)
        _ = await F.send(request, plan: .respond(status: 200, headers: [:], chunks: [Data("x".utf8)]), id: id)
        let sent = try #require(StubBook.shared.requests(id).first)
        let fields = sent.allHTTPHeaderFields ?? [:]
        #expect(fields["User-Agent"] == "Tend")
        #expect(fields["Accept-Language"] == "en-US")
        let allowed = Set(request.headerNames.map { $0.lowercased() })
            .union(CloudAllowedKeyPaths.transportSetHeaders.map { $0.lowercased() })
        for name in fields.keys {
            #expect(allowed.contains(name.lowercased()), "unexpected header \(name)")
        }
        #expect(fields.keys.contains { $0.caseInsensitiveCompare("Cookie") == .orderedSame } == false)
    }

    @Test("AC-M2-22: a request to a host other than the provider's is refused before sending (nothing reaches the network)",
          arguments: ["api.example.com", "api.openai.com.example.net", "generativelanguage.googleapis.com", ""])
    func otherHost(host: String) async throws {
        let id = F.newID()
        let base = try F.request(.anthropic)
        let request = F.altered(base, host: host, id: id)
        let (chunks, end) = await F.send(request, plan: .respond(status: 200, headers: [:], chunks: [Data("x".utf8)]),
                                         id: id)
        #expect(chunks.isEmpty)
        #expect((end as? CloudTransportFailure)?.reason == .requestNotSent)
        #expect(StubBook.shared.requests(id).isEmpty)
    }

    @Test("AC-M2-22: a non-HTTPS URL is refused before sending: a host that would change the scheme or authority",
          arguments: ["http://api.openai.com", "api.openai.com:80", "user@api.openai.com"])
    func notHTTPS(host: String) async throws {
        let id = F.newID()
        let request = F.altered(try F.request(.openAI), host: host, id: id)
        let (_, end) = await F.send(request, plan: .respond(status: 200, headers: [:], chunks: []), id: id)
        #expect((end as? CloudTransportFailure)?.reason == .requestNotSent)
        #expect(StubBook.shared.requests(id).isEmpty)
        // The URL builder itself never makes anything but https to the provider's host.
        #expect(CloudHTTPTransport.urlRequest(request, timeouts: F.timeouts) == nil)
    }

    @Test("A header value with a line break is refused before sending (no header injection; review R28-F5)")
    func lineBreakHeader() async throws {
        let id = F.newID()
        let injected = CloudRequestHeader(name: "X-Extra", content: .text("a\r\nCookie: x"))
        let request = F.altered(try F.request(.gemini), extraHeader: injected, id: id)
        let (_, end) = await F.send(request, plan: .respond(status: 200, headers: [:], chunks: []), id: id)
        #expect((end as? CloudTransportFailure)?.reason == .requestNotSent)
        #expect(StubBook.shared.requests(id).isEmpty)
    }

    @Test("AC-M2-22: a redirect to another host is not followed and ends requestNotSent; nothing is sent there")
    func redirectOtherHost() async throws {
        let id = F.newID()
        let request = F.altered(try F.request(.openAI), id: id)
        let (chunks, end) = await F.send(request, plan: .redirect(location: "https://evil.example.com/steal"), id: id)
        #expect(chunks.isEmpty)
        #expect((end as? CloudTransportFailure)?.reason == .requestNotSent)
        let sent = StubBook.shared.requests(id)
        #expect(sent.count == 1)
        #expect(sent.allSatisfy { $0.url?.host == request.host })
    }

    @Test("A redirect on the same host is not followed either; it ends unexpectedResponse")
    func redirectSameHost() async throws {
        let id = F.newID()
        let request = F.altered(try F.request(.openAI), id: id)
        let (_, end) = await F.send(request, plan: .redirect(location: "/v1/elsewhere"), id: id)
        #expect((end as? CloudTransportFailure)?.reason == .unexpectedResponse)
        #expect(StubBook.shared.requests(id).count == 1)
    }

    static let statuses: [(Int, CloudFailureReason)] = [
        (401, .keyNotAccepted), (403, .keyNotAccepted), (429, .rateLimited), (500, .serviceUnavailable),
        (502, .serviceUnavailable), (503, .serviceUnavailable), (599, .serviceUnavailable), (400, .unexpectedResponse),
        (404, .unexpectedResponse), (408, .unexpectedResponse), (304, .unexpectedResponse), (199, .unexpectedResponse),
    ]

    @Test("AC-M2-23: each HTTP status maps to its neutral reason; Retry-After is passed on raw for 429 and 5xx only",
          arguments: statuses.map(\.0))
    func status(code: Int) async throws {
        let expected = try #require(Self.statuses.first { $0.0 == code }?.1)
        let id = F.newID()
        let request = F.altered(try F.request(.anthropic), id: id)
        let (chunks, end) = await F.send(request, plan: .respond(status: code, headers: ["Retry-After": "7"],
                                                                 chunks: [Data("{\"error\":1}".utf8)]), id: id)
        #expect(chunks.isEmpty)
        let failure = try #require(end as? CloudTransportFailure)
        #expect(failure.reason == expected)
        #expect(failure.retryAfter == (expected.allowsRetry ? "7" : nil))
        #expect(StubBook.shared.requests(id).count == 1)   // never retried here
    }

    static let errors: [(URLError.Code, CloudFailureReason)] = [
        (.notConnectedToInternet, .offline), (.networkConnectionLost, .offline), (.dataNotAllowed, .offline),
        (.timedOut, .timedOut), (.cannotFindHost, .hostNotFound), (.dnsLookupFailed, .hostNotFound),
        (.secureConnectionFailed, .secureConnectionUnavailable),
        (.serverCertificateUntrusted, .secureConnectionUnavailable),
        (.serverCertificateHasBadDate, .secureConnectionUnavailable), (.cannotConnectToHost, .unexpectedResponse),
        (.badServerResponse, .unexpectedResponse),
    ]

    @Test("AC-M2-23: each URLError through the session maps to its neutral reason", arguments: errors.map(\.0.rawValue))
    func transportError(raw: Int) async throws {
        let code = URLError.Code(rawValue: raw)
        let expected = try #require(Self.errors.first { $0.0 == code }?.1)
        let id = F.newID()
        let request = F.altered(try F.request(.gemini), id: id)
        let (_, end) = await F.send(request, plan: .fail(code), id: id)
        #expect((end as? CloudTransportFailure)?.reason == expected)
    }

    @Test("AC-M2-23: the mapping table, code by code (every listed code, cancellation is not a failure)")
    func mappingTable() {
        #expect(CloudFailureMapping.dnsLookup == .dnsLookupFailed)
        #expect(CloudFailureMapping.secureConnection == .secureConnectionFailed)
        for (code, reason) in Self.errors { #expect(CloudFailureMapping.reason(for: code) == reason) }
        #expect(CloudFailureMapping.reason(for: .cancelled) == nil)
        for (status, reason) in Self.statuses { #expect(CloudFailureMapping.reason(forStatus: status) == reason) }
        for status in [200, 201, 204, 299] { #expect(CloudFailureMapping.reason(forStatus: status) == nil) }
    }

    @Test("AC-M2-22 (R30-F5): a stub that never answers ends timedOut at the attempt's resource timeout")
    func silentTimesOut() async throws {
        let id = F.newID()
        let request = F.altered(try F.request(.openAI), id: id)
        let clock = ContinuousClock()
        let start = clock.now
        let (_, end) = await F.send(request, plan: .silent, id: id,
                                    timeouts: CloudAttemptTimeouts(resource: 1.0, request: 1.0))
        let elapsed = start.duration(to: clock.now)
        #expect((end as? CloudTransportFailure)?.reason == .timedOut)
        #expect(elapsed < .seconds(5))
    }

    @Test("AC-M2-22 (R30-F5): a body that stops arriving ends timedOut, inside the resource timeout")
    func silentBodyTimesOut() async throws {
        let id = F.newID()
        let request = F.altered(try F.request(.anthropic), id: id)
        let (_, end) = await F.send(request, plan: .silentAfterHeaders, id: id,
                                    timeouts: CloudAttemptTimeouts(resource: 1.5, request: 1.0))
        #expect((end as? CloudTransportFailure)?.reason == .timedOut)
    }

    @Test("Contract 4 and 5 (R30-F2): cancelling mid-body ends without a failure, and CloudResponseBody ends with CancellationError")
    func cancelMidBody() async throws {
        let id = F.newID()
        let request = F.altered(try F.request(.openAI), id: id)
        StubBook.shared.set(.silentAfterHeaders, for: id)
        let transport = F.transport()
        let task = Task { () -> (any Error)? in
            do {
                for try await _ in transport.send(request, timeouts: F.timeouts) {}
                return nil
            } catch { return error }
        }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        let end = await task.value
        #expect(!(end is CloudTransportFailure))
        // Through the neutral body reader: a cancelled reading task ends with CancellationError (contract point 5).
        let body = CloudResponseBody(request: request, transport: transport, clock: ContinuousClock(),
                                     start: ContinuousClock.now)
        let reader = Task { () -> (any Error)? in
            do {
                for try await _ in body {}
                return nil
            } catch { return error }
        }
        try await Task.sleep(for: .milliseconds(300))
        reader.cancel()
        #expect(await reader.value is CancellationError)
    }

    @Test("A stream created inside a cancelled task sends nothing")
    func createdCancelled() async throws {
        let id = F.newID()
        let request = F.altered(try F.request(.gemini), id: id)
        StubBook.shared.set(.respond(status: 200, headers: [:], chunks: [Data("x".utf8)]), for: id)
        let transport = F.transport()
        let task = Task { () -> Int in
            withUnsafeCurrentTask { $0?.cancel() }
            var count = 0
            do { for try await _ in transport.send(request, timeouts: F.timeouts) { count += 1 } } catch {}
            return count
        }
        #expect(await task.value == 0)
        try await Task.sleep(for: .milliseconds(200))
        #expect(StubBook.shared.requests(id).isEmpty)
    }

    @Test("A response's Set-Cookie is never kept or sent back on the next attempt")
    func noCookies() async throws {
        let id = F.newID()
        let request = F.altered(try F.request(.openAI), id: id)
        _ = await F.send(request, plan: .respond(status: 200, headers: ["Set-Cookie": "session=abc; Path=/"],
                                                 chunks: [Data("x".utf8)]), id: id)
        _ = await F.send(request, plan: .respond(status: 200, headers: [:], chunks: [Data("y".utf8)]), id: id)
        let sent = StubBook.shared.requests(id)
        #expect(sent.count == 2)
        #expect(sent.allSatisfy { $0.value(forHTTPHeaderField: "Cookie") == nil })
    }

    @Test("An event ends at a blank line, LF or CRLF; a single line end does not end it")
    func eventEnds() {
        #expect(CloudHTTPTransport.endsEvent(Array("data: x\n\n".utf8)))
        #expect(CloudHTTPTransport.endsEvent(Array("data: x\r\n\r\n".utf8)))
        #expect(!CloudHTTPTransport.endsEvent(Array("data: x\n".utf8)))
        #expect(!CloudHTTPTransport.endsEvent(Array("\n".utf8)))
        #expect(!CloudHTTPTransport.endsEvent([]))
    }
}
