import Foundation

/// Answers the requests of a `URLSession` built by `session(answering:)` from memory, so
/// downloads are tested without the network: no request leaves the process, and the
/// addresses asked for are recorded.
final class CommunityPluginDownloadStub: URLProtocol {
    struct Answer {
        var statusCode = 200
        var headers: [String: String] = [:]
        var body = Data()

        static let notFound = Answer(statusCode: 404)
        static func ok(_ body: Data, headers: [String: String] = [:]) -> Answer { Answer(statusCode: 200, headers: headers, body: body) }
    }

    private final class State: @unchecked Sendable {
        // Requests arrive on URL loading threads; the lock orders them.
        private let lock = NSLock()
        private var responder: (@Sendable (URL) -> Answer)?
        private var addresses: [URL] = []

        func install(_ newResponder: @escaping @Sendable (URL) -> Answer) { lock.withLock { responder = newResponder; addresses = [] } }
        func answer(for address: URL) -> Answer {
            let currentResponder = lock.withLock { () -> (@Sendable (URL) -> Answer)? in addresses.append(address); return responder }
            return currentResponder?(address) ?? .notFound
        }
        var requestedAddresses: [URL] { lock.withLock { addresses } }
    }

    private static let state = State()

    /// The addresses asked for since the last `session(answering:)`.
    static var requestedAddresses: [URL] { state.requestedAddresses }

    static func session(answering responder: @escaping @Sendable (URL) -> Answer) -> URLSession {
        state.install(responder)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CommunityPluginDownloadStub.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let address = request.url else { return }
        let answer = Self.state.answer(for: address)
        guard let response = HTTPURLResponse(url: address, statusCode: answer.statusCode, httpVersion: "HTTP/1.1", headerFields: answer.headers) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// JSON text followed by spaces up to exactly `byteCount` bytes: still valid JSON, so a
/// size limit is tested with a file the reader would accept if the limit allowed it.
func paddedJSON(_ json: String, toBytes byteCount: Int) -> Data {
    let text = Data(json.utf8)
    precondition(text.count <= byteCount)
    return text + Data(repeating: UInt8(ascii: " "), count: byteCount - text.count)
}
