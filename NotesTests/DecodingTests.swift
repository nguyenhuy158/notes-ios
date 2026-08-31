import XCTest
@testable import Notes

/// JSON o day copy dang that cua worker (toNoteJson trong worker/src/index.ts).
/// Muc dich: server them field moi khong duoc lam app vo, va field app dung
/// phai doc dung.
final class DecodingTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testNoteWithGallery() throws {
        let response = try decode(NotesResponse.self, """
        {"notes":[{"id":"n1","date":"2026-09-01","type":"photo","text":"biển",
        "mime":"image/jpeg","mood":"😄","pinned":true,"tags":["dulich","bien"],
        "shareToken":null,"location":"Đà Nẵng",
        "mediaUrl":"/api/media/n1?v=1","mediaUrls":["/api/media/n1?v=1","/api/media/n1?slot=1&v=1"],
        "createdAt":"2026-09-01 10:00:00","updatedAt":"2026-09-01 10:00:00","deletedAt":null,
        "fieldMoiToanhServerVuaThem":123}]}
        """)
        let note = response.notes[0]
        XCTAssertEqual(note.id, "n1")
        XCTAssertEqual(note.type, "photo")
        XCTAssertEqual(note.mood, "😄")
        XCTAssertTrue(note.pinned)
        XCTAssertEqual(note.tags, ["dulich", "bien"])
        XCTAssertEqual(note.location, "Đà Nẵng")
        XCTAssertEqual(note.mediaUrls.count, 2)
    }

    func testTextNoteHasNullMedia() throws {
        let response = try decode(NoteResponse.self, "{\"note\":\(noteJson)}")
        XCTAssertNil(response.note.mediaUrl)
        XCTAssertTrue(response.note.mediaUrls.isEmpty)
        XCTAssertNil(response.note.mood)
        XCTAssertFalse(response.note.pinned)
    }

    func testDays() throws {
        let days = try decode(DaysResponse.self, """
        {"days":{"2026-09-01":["text","photo"],"2026-09-02":["text"]},
         "moods":{"2026-09-01":"😄"},
         "tags":{"2026-09-01":["dulich"]}}
        """)
        XCTAssertEqual(days.days["2026-09-01"]?.count, 2)
        XCTAssertEqual(days.moods["2026-09-01"], "😄")
        XCTAssertNil(days.moods["2026-09-02"])
        XCTAssertEqual(days.tags["2026-09-01"], ["dulich"])
    }

    func testMeAndStats() throws {
        let me = try decode(MeResponse.self, "{\"email\":\"a@b.c\",\"name\":\"Huy\"}")
        XCTAssertEqual(me.name, "Huy")
        let stats = try decode(StatsResponse.self, "{\"noteCount\":12,\"mediaBytes\":2048}")
        XCTAssertEqual(formatBytes(stats.mediaBytes), "2.0 KB")
    }

    /// Note type "video" (worker moi them) phai doc duoc, chi la app khong tao ra.
    func testUnknownTypeStillDecodes() throws {
        let response = try decode(NotesResponse.self, """
        {"notes":[{"id":"n2","date":"2026-09-01","type":"video","text":"","mime":"video/mp4",
        "mood":null,"pinned":false,"tags":[],"shareToken":null,"location":null,
        "mediaUrl":"/api/media/n2?v=1","mediaUrls":["/api/media/n2?v=1"],
        "createdAt":"2026-09-01 10:00:00","updatedAt":"2026-09-01 10:00:00","deletedAt":null}]}
        """)
        XCTAssertEqual(response.notes[0].type, "video")
        XCTAssertEqual(noteTypeLabel(response.notes[0].type), "Video")
    }
}
