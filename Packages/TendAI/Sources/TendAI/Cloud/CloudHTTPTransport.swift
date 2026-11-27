// The HTTPS cloud transport (WI-M2-M4; brief AC-M2-22, AC-M2-23; ADR-0005 Decisions 6 and 7; `CloudTransport`
// contract points 1-5). P-2, P-3, P-4.
//
// Allowlist file 1 of the cloud adapter (AC-M2-09 Rule 3): the only file that builds a URL or a session.
// - **One attempt per call**, on its own ephemeral session: no cookie storage, no URL cache, no credential storage,
//   cookies neither sent nor kept; `timeoutIntervalForResource` and `timeoutIntervalForRequest` from the attempt's
//   `CloudAttemptTimeouts`. Never retried here (the retry is `CloudResponseBody`'s).
// - **HTTPS to the routed provider's host only.** The URL is built with `URLComponents` from the builder's bare host and
//   path, scheme `https`. A request whose host is not the ADR-0005 host of its provider, a URL that is not HTTPS, or a
//   header value with a line break is refused before anything is sent (`requestNotSent`).
// - **No redirect is followed.** The task delegate answers every redirect with nil. A redirect to another host ends as
//   `requestNotSent` (nothing was sent there); any other 3xx is `unexpectedResponse`.
// - **Headers:** exactly the builder's headers (auth, provider, `User-Agent: Tend`, `Accept-Language: en-US`), set
//   explicitly so the device's defaults are never sent. The session adds only the transport-set headers.
// - **Body:** a 2xx body is passed on in chunks of up to 4 KiB, cut after each blank line (the end of a server-sent
//   event), so every whole event goes on at once and no chunk is a single byte (review R29-N2). Any other status throws `CloudTransportFailure`, with the raw `Retry-After` for 429 and 5xx.
// - **Cancellation** (contract point 5): `onTermination` cancels the task and the session; a cancelled attempt finishes
//   without an error.
// Nothing is logged or written: the body and the key live only in memory for the attempt (P-4).

import Foundation
import TendIngestion

public struct CloudHTTPTransport: CloudTransport {
    /// Tests only: a hook that adjusts each attempt's session configuration (the `URLProtocol` stub). The app passes
    /// nothing.
    let adjust: @Sendable (URLSessionConfiguration) -> Void

    public init() {
        self.init(adjust: { _ in })
    }

    init(adjust: @escaping @Sendable (URLSessionConfiguration) -> Void) {
        self.adjust = adjust
    }

    /// The configuration of one attempt.
    static func configuration(_ timeouts: CloudAttemptTimeouts) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForResource = timeouts.resource
        configuration.timeoutIntervalForRequest = timeouts.request
        configuration.waitsForConnectivity = false
        return configuration
    }

    /// The ADR-0005 host of `provider`.
    static func routedHostName(_ provider: CloudProvider) -> String? {
        zip(CloudProvider.allCases, CloudProviderTable.hosts).first { $0.0 == provider }?.1
    }

    /// The URL request for `request`, or nil when it must be refused before sending.
    static func urlRequest(_ request: CloudRequest, timeouts: CloudAttemptTimeouts) -> URLRequest? {
        guard let allowed = routedHostName(request.provider), request.host == allowed else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = request.host
        components.path = request.path
        if !request.queryItems.isEmpty {
            // Fixed names and values from the provider table (for example `alt=sse`); `query` percent-encodes them.
            components.query = request.queryItems.map { $0.name + "=" + $0.value }.joined(separator: "&")
        }
        guard let url = components.url, url.scheme == "https", url.host == allowed else { return nil }
        var urlRequest = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                                    timeoutInterval: timeouts.request)
        urlRequest.httpMethod = request.method
        urlRequest.httpShouldHandleCookies = false
        for header in request.headers {
            let safe = header.withValue { value in
                guard !Self.hasLineBreak(value), !Self.hasLineBreak(header.name) else { return false }
                urlRequest.setValue(value, forHTTPHeaderField: header.name)
                return true
            }
            guard safe else { return nil }
        }
        urlRequest.httpBody = request.body
        return urlRequest
    }

    static func hasLineBreak(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0 == "\r" || $0 == "\n" || $0 == "\0" }
    }

    public func send(_ request: CloudRequest,
                     timeouts: CloudAttemptTimeouts) -> AsyncThrowingStream<[UInt8], any Error> {
        let adjust = adjust
        return AsyncThrowingStream { continuation in
            guard !Task.isCancelled else {
                continuation.finish()
                return
            }
            guard let urlRequest = Self.urlRequest(request, timeouts: timeouts), let allowed = urlRequest.url?.host else {
                continuation.finish(throwing: CloudTransportFailure(.requestNotSent))
                return
            }
            let configuration = Self.configuration(timeouts)
            adjust(configuration)
            let session = URLSession(configuration: configuration)
            let task = Task {
                do {
                    let refuser = RedirectRefuser()
                    let (stream, response) = try await session.bytes(for: urlRequest, delegate: refuser)
                    guard let http = response as? HTTPURLResponse else {
                        throw CloudTransportFailure(.unexpectedResponse)
                    }
                    if (300...399).contains(http.statusCode) {
                        throw CloudTransportFailure(Self.pointsElsewhere(http, allowed) ? .requestNotSent
                                                        : .unexpectedResponse)
                    }
                    if let reason = CloudFailureMapping.reason(forStatus: http.statusCode) {
                        let retryAfter = CloudFailureMapping.passesRetryAfter(reason)
                            ? http.value(forHTTPHeaderField: "Retry-After") : nil
                        throw CloudTransportFailure(reason, retryAfter: retryAfter)
                    }
                    var chunk: [UInt8] = []
                    chunk.reserveCapacity(Self.chunkLimit)
                    for try await byte in stream {
                        chunk.append(byte)
                        if Self.endsEvent(chunk) || chunk.count >= Self.chunkLimit {
                            continuation.yield(chunk)
                            chunk.removeAll(keepingCapacity: true)
                        }
                    }
                    if !chunk.isEmpty { continuation.yield(chunk) }
                    continuation.finish()
                } catch let failure as CloudTransportFailure {
                    continuation.finish(throwing: failure)
                } catch let error as URLError {
                    if let reason = CloudFailureMapping.reason(for: error), !Task.isCancelled {
                        continuation.finish(throwing: CloudTransportFailure(reason))
                    } else {
                        continuation.finish()
                    }
                } catch {
                    if Task.isCancelled || error is CancellationError {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: CloudTransportFailure(.unexpectedResponse))
                    }
                }
                session.finishTasksAndInvalidate()
            }
            continuation.onTermination = { _ in
                task.cancel()
                session.invalidateAndCancel()
            }
        }
    }

    /// The most bytes in one chunk.
    static let chunkLimit = 4_096

    /// The chunk ends with a blank line (`\n\n` or `\n\r\n`): the end of one server-sent event.
    static func endsEvent(_ chunk: [UInt8]) -> Bool {
        guard chunk.count >= 2, chunk[chunk.count - 1] == 0x0A else { return false }
        if chunk[chunk.count - 2] == 0x0A { return true }
        return chunk.count >= 3 && chunk[chunk.count - 2] == 0x0D && chunk[chunk.count - 3] == 0x0A
    }

    /// A redirect response that points at a host other than the routed one.
    static func pointsElsewhere(_ response: HTTPURLResponse, _ allowed: String) -> Bool {
        guard let location = response.value(forHTTPHeaderField: "Location") else { return false }
        guard let target = URLComponents(string: location), let host = target.host else { return false }
        return host.lowercased() != allowed.lowercased()
    }
}

/// Answers every redirect with nil, so none is followed (AC-M2-22). Stateless.
final class RedirectRefuser: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}
