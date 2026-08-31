import XCTest
@testable import Notes

/// Chan moi request cua URLSession rieng cua test — khong he goi mang thuc.
final class StubProtocol: URLProtocol {
    /// (status, body) tra ve, hoac loi mang. Dat truoc moi test.
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data("{}".utf8)
    nonisolated(unsafe) static var failure: Error?
    /// Request cuoi cung di qua — de kiem method/header/body.
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        // URLSession doi httpBody thanh stream truoc khi den day.
        Self.lastBody = request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
            return data
        }

        if let failure = Self.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class ApiClientTests: XCTestCase {
    private var client: ApiClient!

    override func setUp() {
        super.setUp()
        StubProtocol.status = 200
        StubProtocol.body = Data("{}".utf8)
        StubProtocol.failure = nil
        StubProtocol.lastRequest = nil
        StubProtocol.lastBody = nil

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        client = ApiClient(token: "tok", session: URLSession(configuration: config))
    }

    private func expectError(_ body: () async throws -> Void) async -> ApiError? {
        do {
            try await body()
            return nil
        } catch let error as ApiError {
            return error
        } catch {
            XCTFail("loi la: \(error)")
            return nil
        }
    }

    /// Cai de sai am tham nhat: worker notes doc COOKIE, khong doc Bearer.
    func testGetSendsSsoCookieAndDecodes() async throws {
        StubProtocol.body = Data("{\"noteCount\":3,\"mediaBytes\":1024}".utf8)
        let stats: StatsResponse = try await client.get("/api/stats")
        XCTAssertEqual(stats.noteCount, 3)
        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(StubProtocol.lastRequest?.url?.absoluteString,
                       "https://notes.huyab.click/api/stats")
        XCTAssertEqual(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Cookie"),
                       "huyab_sso=tok")
        XCTAssertNil(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"))
    }

    func testPutEncodesJson() async throws {
        StubProtocol.body = Data("{\"note\":\(noteJson)}".utf8)
        let _: NoteResponse = try await client.put("/api/notes/1", body: TextInput(text: "xin chào"))
        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "PUT")
        XCTAssertEqual(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type"),
                       "application/json")
        let sent = try JSONSerialization.jsonObject(with: StubProtocol.lastBody ?? Data()) as? [String: Any]
        XCTAssertEqual(sent?["text"] as? String, "xin chào")
    }

    /// mood = nil phai gui `{"mood":null}` de server biet la bo mood, chu khong
    /// phai bo han field (bo han thi server hieu la khong doi).
    func testMoodNullIsSentExplicitly() async throws {
        StubProtocol.body = Data("{\"note\":\(noteJson)}".utf8)
        let _: NoteResponse = try await client.put("/api/notes/1/mood", body: MoodInput(mood: nil))
        let raw = String(data: StubProtocol.lastBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(raw.contains("\"mood\":null"), raw)
    }

    func testCreateNoteSendsMultipart() async throws {
        StubProtocol.body = Data("{\"note\":\(noteJson)}".utf8)
        let note = NewNote(date: "2026-09-01", text: "chú thích", mood: "😄",
                           location: "Hà Nội", tags: ["ăn"], photos: [Data("fake-jpeg".utf8)])
        _ = try await client.createNote(note)

        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "POST")
        let contentType = StubProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type") ?? ""
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="), contentType)

        let body = String(data: StubProtocol.lastBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("name=\"type\"\r\n\r\nphoto"), body)
        XCTAssertTrue(body.contains("name=\"location\"\r\n\r\nHà Nội"))
        XCTAssertTrue(body.contains("filename=\"photo-0.jpg\""))
        XCTAssertTrue(body.contains("Content-Type: image/jpeg"))
    }

    func testFireIgnoresEmptyBody() async throws {
        StubProtocol.body = Data()          // body rong van phai coi la thanh cong
        try await client.fire("/api/notes/1", method: "DELETE")
        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "DELETE")
    }

    func testMediaReturnsRawBytes() async throws {
        StubProtocol.body = Data([1, 2, 3])
        let data = try await client.media("/api/media/1?v=x")
        XCTAssertEqual(data, Data([1, 2, 3]))
    }

    func testUnauthorized() async {
        StubProtocol.status = 401
        let error = await expectError { try await self.client.fire("/api/notes/1", method: "DELETE") }
        XCTAssertEqual(error?.errorDescription, ApiError.unauthorized.errorDescription)
    }

    func testMediaUnauthorized() async {
        StubProtocol.status = 401
        let error = await expectError { _ = try await self.client.media("/api/media/1") }
        XCTAssertEqual(error?.errorDescription, ApiError.unauthorized.errorDescription)
    }

    func testNonSuccessStatus() async {
        StubProtocol.status = 500
        let error = await expectError { try await self.client.fire("/api/notes/1", method: "DELETE") }
        XCTAssertEqual(error?.errorDescription, "Máy chủ trả lỗi 500")
    }

    func testTransportFailure() async {
        StubProtocol.failure = URLError(.notConnectedToInternet)
        let error = await expectError { try await self.client.fire("/api/trash", method: "GET") }
        XCTAssertNotNil(error?.errorDescription)
    }

    func testDecodeFailureIsReported() async {
        StubProtocol.body = Data("[]".utf8)      // array trong khi cho object
        let error = await expectError {
            let _: StatsResponse = try await self.client.get("/api/stats")
        }
        XCTAssertTrue(error?.errorDescription?.contains("đọc được") ?? false, "\(error as Any)")
    }
}

let noteJson = """
{"id":"n1","date":"2026-09-01","type":"text","text":"hi","mime":null,"mood":null,
 "pinned":false,"tags":[],"shareToken":null,"location":null,"mediaUrl":null,
 "mediaUrls":[],"createdAt":"2026-09-01 10:00:00","updatedAt":"2026-09-01 10:00:00","deletedAt":null}
"""
