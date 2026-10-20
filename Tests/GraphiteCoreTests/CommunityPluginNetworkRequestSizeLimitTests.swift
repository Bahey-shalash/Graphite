import XCTest
@testable import GraphiteCore

/// The answer to a plugin's `requestUrl` is bounded: exactly 64 MiB is delivered, one byte
/// more is refused with `oversized`, whether the server announces its size or not. The
/// session answers from memory, so no request leaves the process.
final class CommunityPluginNetworkRequestSizeLimitTests: XCTestCase {
    private static let address = "https://plugin-request.test/data"

    private func request() throws -> CommunityPluginNetworkRequest {
        try JSONDecoder().decode(CommunityPluginNetworkRequest.self, from: Data(#"{"url": "\#(Self.address)", "method": "get", "headers": {}}"#.utf8))
    }

    private func assertOversized(file: StaticString = #filePath, line: UInt = #line, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("The answer should have been refused as oversized.", file: file, line: line)
        } catch GraphiteError.oversized {
        } catch {
            XCTFail("The request failed with \(error) instead of oversized.", file: file, line: line)
        }
    }

    func testTheCapIsSixtyFourMebibytes() {
        XCTAssertEqual(CommunityPluginNetworkRequest.maximumResponseBytes, 64 * 1_048_576)
    }

    func testAnAnswerThatAnnouncesMoreThanTheCapIsRefusedBeforeItIsRead() async throws {
        let cap = CommunityPluginNetworkRequest.maximumResponseBytes
        let session = CommunityPluginDownloadStub.session { _ in .ok(Data("tiny".utf8), headers: ["Content-Length": String(cap + 1)]) }
        let plannedRequest = try request()
        await assertOversized { _ = try await plannedRequest.perform(using: session) }
        XCTAssertEqual(CommunityPluginDownloadStub.requestedAddresses.map(\.absoluteString), [Self.address])
    }

    func testAnAnswerOfExactlyTheCapIsDeliveredAndOneByteMoreIsRefused() async throws {
        let cap = CommunityPluginNetworkRequest.maximumResponseBytes
        let atCapSession = CommunityPluginDownloadStub.session { _ in .ok(Data(count: cap)) }
        let atCap = try await request().perform(using: atCapSession)
        XCTAssertEqual(atCap.status, 200)
        XCTAssertEqual(atCap.body.count, cap)

        let overCapSession = CommunityPluginDownloadStub.session { _ in .ok(Data(count: cap + 1)) }
        let plannedRequest = try request()
        await assertOversized { _ = try await plannedRequest.perform(using: overCapSession) }
    }
}
