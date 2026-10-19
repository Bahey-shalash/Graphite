import XCTest
@testable import GraphiteCore

/// A plugin's `requestUrl` as Graphite makes it: only web addresses, the method in capitals,
/// the plugin's content type and base64 body, and the answer as the runtime reads it.
final class CommunityPluginNetworkRequestTests: XCTestCase {
    override func setUp() {
        ScriptedWebProtocol.recorder.reset()
    }

    override func tearDown() {
        ScriptedWebProtocol.recorder.reset()
    }

    private func scriptedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScriptedWebProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func request(_ fields: [String: Any]) throws -> CommunityPluginNetworkRequest {
        try JSONDecoder().decode(CommunityPluginNetworkRequest.self, from: JSONSerialization.data(withJSONObject: fields))
    }

    func testOnlyHttpAndHttpsAddressesAreRequested() async throws {
        for address in ["file:///etc/passwd", "ftp://example.com/file", "graphite-plugins://vault/Note.md", "data:text/plain,hello", "javascript:alert(1)", "example.com/no-scheme", ""] {
            let rejected = try request(["url": address, "method": "GET", "headers": [String: String]()])
            do {
                _ = try await rejected.perform(using: scriptedSession())
                XCTFail("\(address) is not a web address.")
            } catch GraphiteError.unavailable {
                // The expected refusal.
            }
        }
        XCTAssertTrue(ScriptedWebProtocol.recorder.requests.isEmpty, "Nothing is sent for a refused address.")
        for address in ["https://example.com/a", "HTTP://example.com/b"] {
            _ = try await request(["url": address, "method": "get", "headers": [String: String]()]).perform(using: scriptedSession())
        }
        XCTAssertEqual(ScriptedWebProtocol.recorder.requests.map(\.address), ["https://example.com/a", "HTTP://example.com/b"])
    }

    func testTheMethodIsUppercasedAndTheContentTypeAndBodyAreSent() async throws {
        let body = Data("{\"a\":1}".utf8)
        _ = try await request([
            "url": "https://example.com/api", "method": "post", "headers": ["X-Token": "abc"],
            "contentType": "application/json", "bodyBase64": body.base64EncodedString(),
        ]).perform(using: scriptedSession())

        let sent = try XCTUnwrap(ScriptedWebProtocol.recorder.requests.first)
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.headers["Content-Type"], "application/json")
        XCTAssertEqual(sent.headers["X-Token"], "abc")
        XCTAssertEqual(sent.body, body)
    }

    func testTheAnswerHasTheStatusLowercasedHeaderNamesAndTheBodyInBase64() async throws {
        let response = try await request(["url": "https://example.com/answer", "method": "GET", "headers": [String: String]()]).perform(using: scriptedSession())

        XCTAssertEqual(response.status, 201)
        XCTAssertEqual(response.headers["content-type"], "text/plain")
        XCTAssertEqual(response.headers["x-custom-header"], "Value")
        XCTAssertNil(response.headers["Content-Type"])
        XCTAssertEqual(response.body, Data("scripted answer".utf8))
        let json = response.jsonObject
        XCTAssertEqual(Set(json.keys), ["status", "headers", "bodyBase64"])
        XCTAssertEqual(json["status"] as? Int, 201)
        XCTAssertEqual(json["bodyBase64"] as? String, Data("scripted answer".utf8).base64EncodedString())
        XCTAssertEqual(json["headers"] as? [String: String], ["content-type": "text/plain", "x-custom-header": "Value", "content-length": "15"])
    }

    func testABodyThatIsNotBase64IsRefusedBeforeAnythingIsSent() async throws {
        do {
            _ = try await request(["url": "https://example.com/api", "method": "POST", "headers": [String: String](), "bodyBase64": "***not base64***"]).perform(using: scriptedSession())
            XCTFail("A body that is not base64 cannot be sent.")
        } catch GraphiteError.invalidFile {
            // The expected refusal.
        }
        XCTAssertTrue(ScriptedWebProtocol.recorder.requests.isEmpty)
    }
}

/// Answers every request with a fixed response and records what was sent.
private final class ScriptedWebProtocol: URLProtocol {
    struct SentRequest: Sendable {
        let address: String
        let method: String
        let headers: [String: String]
        let body: Data?
    }

    final class Recorder: @unchecked Sendable {
        // Requests arrive on URL loading threads; the lock orders them.
        private let lock = NSLock()
        private var sent: [SentRequest] = []
        var requests: [SentRequest] { lock.withLock { sent } }
        func record(_ request: SentRequest) { lock.withLock { sent.append(request) } }
        func reset() { lock.withLock { sent = [] } }
    }

    static let recorder = Recorder()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.recorder.record(SentRequest(address: url.absoluteString, method: request.httpMethod ?? "", headers: request.allHTTPHeaderFields ?? [:], body: Self.bodyOf(request)))
        let headers = ["Content-Type": "text/plain", "X-Custom-Header": "Value", "Content-Length": "15"]
        guard let response = HTTPURLResponse(url: url, statusCode: 201, httpVersion: "HTTP/1.1", headerFields: headers) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("scripted answer".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// A request's body arrives as a stream by the time a protocol sees it.
    private static func bodyOf(_ request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
