import Foundation
import Testing
@testable import SyllapaceKit

private actor SchoolTransport: HTTPTransport {
    var requests: [URLRequest] = []
    private let reply: HTTPReply
    init(_ reply: HTTPReply) { self.reply = reply }
    func send(_ request: URLRequest, maxBytes: Int) async throws -> HTTPReply {
        try Task.checkCancellation()
        requests.append(request)
        return reply
    }
}

@Suite("Canvas school directory")
struct SchoolDirectoryTests {
    @Test func lookupIsAnonymousAndCachesNormalizedQueries() async throws {
        let data = Data(#"[{"id":128499,"name":"Carnegie Mellon University","domain":"canvas.cmu.edu","distance":null,"authentication_provider":null}]"#.utf8)
        let transport = SchoolTransport(HTTPReply(data: data))
        let directory = CanvasSchoolDirectory(transport: transport)
        let first = try await directory.search(name: " Carnegie ")
        let second = try await directory.search(name: "carnegie")
        #expect(first == second)
        #expect(first.first?.url.absoluteString == "https://canvas.cmu.edu")
        let requests = await transport.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.url?.host == "canvas.instructure.com")
        #expect(request.url?.path == "/api/v1/accounts/search")
        #expect(request.url?.query == "name=Carnegie")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
    }

    @Test func malformedAndPrivateDirectoryDestinationsAreNotOffered() async throws {
        let data = Data(#"[{"name":"HTTP","domain":"http://school.example"},{"name":"Private","domain":"127.0.0.1"},{"name":"Credentials","domain":"https://user:password@school.example"},{"name":"Query","domain":"school.example?token=test"},{"name":"Good","domain":"canvas.school.example"},{"name":"Duplicate","domain":"canvas.school.example"}]"#.utf8)
        let directory = CanvasSchoolDirectory(transport: SchoolTransport(HTTPReply(data: data)))
        let schools = try await directory.search(name: "School")
        #expect(schools.count == 1)
        #expect(schools.first?.name == "Good")
    }

    @Test func emptyQueriesDoNotCallTheDirectoryAndRedirectsAreRefused() async throws {
        let transport = SchoolTransport(HTTPReply(data: Data(), status: 302, headers: ["Location": "https://other.example/search"]))
        let directory = CanvasSchoolDirectory(transport: transport)
        #expect(try await directory.search(name: " ").isEmpty)
        #expect(try await directory.search(name: "x").isEmpty)
        #expect(await transport.requests.isEmpty)
        await #expect(throws: ConnectorError.unsafeRedirect) { try await directory.search(name: "School") }
        #expect(await transport.requests.count == 1)
    }

    @Test func unicodeSearchIsEncodedAsOneParameter() async throws {
        let transport = SchoolTransport(HTTPReply(data: Data("[]".utf8)))
        let directory = CanvasSchoolDirectory(transport: transport)
        _ = try await directory.search(name: "大学 & School")
        let requests = await transport.requests
        let url = try #require(requests.first?.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.queryItems == [URLQueryItem(name: "name", value: "大学 & School")])
    }
}
