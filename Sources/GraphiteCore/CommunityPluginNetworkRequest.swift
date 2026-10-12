import Foundation

/// An HTTP request a plugin makes with Obsidian's `requestUrl`. Graphite makes it, as
/// Obsidian mobile does, so it is not bound by the plugin page's cross-origin rules.
/// Only web addresses are allowed, and the answer is bounded in size and time.
public struct CommunityPluginNetworkRequest: Decodable, Sendable {
    public let url: String
    public let method: String
    public let headers: [String: String]
    public let contentType: String?
    public let bodyBase64: String?

    public static let maximumResponseBytes = 64 * 1_048_576
    public static let timeoutSeconds: TimeInterval = 60

    public struct Response: Sendable {
        public let status: Int
        public let headers: [String: String]
        public let body: Data

        /// As the runtime reads it.
        public var jsonObject: [String: Any] {
            ["status": status, "headers": headers, "bodyBase64": body.base64EncodedString()]
        }
    }

    public func perform(using session: URLSession = .shared) async throws -> Response {
        guard let address = URL(string: url), let scheme = address.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            throw GraphiteError.unavailable("Plugins can only request web addresses (https or http).")
        }
        var request = URLRequest(url: address, timeoutInterval: Self.timeoutSeconds)
        request.httpMethod = method.uppercased()
        for (headerName, headerValue) in headers { request.setValue(headerValue, forHTTPHeaderField: headerName) }
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let bodyBase64 {
            guard let body = Data(base64Encoded: bodyBase64) else { throw GraphiteError.invalidFile("The plugin's request body is not valid.") }
            request.httpBody = body
        }
        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw GraphiteError.unavailable("The server did not answer over HTTP.") }
        if httpResponse.expectedContentLength > Int64(Self.maximumResponseBytes) {
            throw GraphiteError.oversized("The answer to the plugin's request is larger than Graphite accepts.")
        }
        var body = Data()
        for try await byte in bytes {
            body.append(byte)
            if body.count > Self.maximumResponseBytes { throw GraphiteError.oversized("The answer to the plugin's request is larger than Graphite accepts.") }
        }
        var responseHeaders: [String: String] = [:]
        for (headerName, headerValue) in httpResponse.allHeaderFields {
            if let headerName = headerName as? String { responseHeaders[headerName.lowercased()] = "\(headerValue)" }
        }
        return Response(status: httpResponse.statusCode, headers: responseHeaders, body: body)
    }
}
