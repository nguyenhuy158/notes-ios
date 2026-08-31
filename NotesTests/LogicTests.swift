import XCTest
@testable import Notes

final class LogicTests: XCTestCase {
    func testJwtExpiry() {
        // {"exp":2000000000} base64url khong padding — dung dang SSO tra ve.
        let usable = "header.eyJleHAiOjIwMDAwMDAwMDB9.sig"
        XCTAssertEqual(SsoToken.expiry(usable), Date(timeIntervalSince1970: 2_000_000_000))
        XCTAssertTrue(SsoToken.isUsable(usable))

        // {"exp":1000000000} — nam 2001.
        XCTAssertFalse(SsoToken.isUsable("header.eyJleHAiOjEwMDAwMDAwMDB9.sig"))
        XCTAssertFalse(SsoToken.isUsable("khong-phai-jwt"))
        XCTAssertNil(SsoToken.expiry("a.b.c"))
    }

    /// Token chet trong 30 giay: con han that, nhung dung de mo app.
    func testExpiringTokenIsNotUsable() {
        let exp = Int(Date().timeIntervalSince1970) + 30
        let payload = Data("{\"exp\":\(exp)}".utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        XCTAssertFalse(SsoToken.isUsable("h.\(payload).s"))
    }

    func testShiftMonthCrossesYear() {
        XCTAssertEqual(shiftMonth("2026-01", by: -1), "2025-12")
        XCTAssertEqual(shiftMonth("2026-12", by: 1), "2027-01")
        XCTAssertEqual(shiftMonth("2026-09", by: -3), "2026-06")
        XCTAssertEqual(shiftMonth("khong-phai-thang", by: 1), "khong-phai-thang")
    }

    func testFormatters() {
        XCTAssertEqual(formatMonthTitle("2026-09"), "Tháng 9, 2026")
        XCTAssertEqual(formatMonthTitle("hong"), "hong")
        XCTAssertEqual(formatBytes(0), "0 B")
        XCTAssertEqual(formatBytes(1536), "1.5 KB")
        XCTAssertEqual(formatBytes(5 * 1024 * 1024), "5.0 MB")
        // Ngay khong doc duoc thi tra ve nguyen ban, khong bo trong.
        XCTAssertEqual(formatDayTitle("hong-phai-ngay"), "hong-phai-ngay")
        XCTAssertTrue(formatDayTitle("2026-09-01").contains("2026") == false)
        XCTAssertEqual(formatDayTitle("2026-09-01").first?.isUppercase, true)
    }

    /// created_at cua D1 khong co chu "T" — ISO8601DateFormatter tra nil, phai
    /// co nhanh du phong khong thi gio nao cung hien ra chuoi tho.
    func testSqliteTimestampParses() {
        XCTAssertNotNil(parseIso("2026-09-01 10:00:00"))
        XCTAssertNotNil(parseIso("2026-09-01T10:00:00Z"))
        XCTAssertNotNil(parseIso("2026-09-01T10:00:00.123Z"))
        XCTAssertNil(parseIso("hong"))
        XCTAssertEqual(formatTime("hong"), "hong")
    }

    func testDayRoundTrip() {
        let date = parseDay("2026-09-01")!
        XCTAssertEqual(dayString(date), "2026-09-01")
        XCTAssertEqual(monthString(date), "2026-09")
    }

    func testTagInputRespectsServerLimits() {
        XCTAssertEqual(parseTagInput(" ăn ,, uống,"), ["ăn", "uống"])
        XCTAssertEqual(parseTagInput("a,a,b"), ["a", "b"])                   // bo trung
        XCTAssertEqual(parseTagInput("1,2,3,4,5,6,7").count, 5)             // MAX_TAGS
        XCTAssertEqual(parseTagInput(String(repeating: "x", count: 40)).first?.count, 24)
        XCTAssertTrue(parseTagInput("   ").isEmpty)
    }

    func testNewNoteFields() {
        let text = NewNote(date: "2026-09-01", text: "hi", mood: nil, location: "",
                           tags: [], photos: [])
        XCTAssertFalse(text.isPhoto)
        XCTAssertTrue(text.fields.contains { $0 == ("type", "text") })
        XCTAssertFalse(text.fields.contains { $0.0 == "mood" })
        XCTAssertFalse(text.fields.contains { $0.0 == "location" })
        XCTAssertTrue(text.files.isEmpty)

        let photo = NewNote(date: "2026-09-01", text: "", mood: "😄", location: "Nhà",
                            tags: ["a", "b"], photos: [Data([1]), Data([2])])
        XCTAssertTrue(photo.isPhoto)
        XCTAssertTrue(photo.fields.contains { $0 == ("type", "photo") })
        XCTAssertTrue(photo.fields.contains { $0 == ("mood", "😄") })
        XCTAssertTrue(photo.fields.contains { $0 == ("tags", "a,b") })
        // Moi anh cung ten field "file" — worker gom lai thanh gallery.
        XCTAssertEqual(photo.files.map(\.name), ["file", "file"])
        XCTAssertEqual(photo.files.map(\.filename), ["photo-0.jpg", "photo-1.jpg"])
    }

    /// Note audio: type="audio", dung 1 file m4a, va chu de rong de worker
    /// chay Whisper. Anh bi bo qua vi worker chi nhan 1 file cho loai nay.
    func testAudioNoteTakesOneFileAndNoText() {
        let note = NewNote(date: "2026-09-01", text: "", mood: nil, location: "",
                           tags: [], photos: [Data([1])], audio: Data("m4a".utf8))
        XCTAssertFalse(note.isPhoto)
        XCTAssertEqual(note.type, "audio")
        XCTAssertTrue(note.fields.contains { $0 == ("text", "") })
        XCTAssertEqual(note.files.count, 1)
        XCTAssertEqual(note.files[0].mime, "audio/mp4")
        XCTAssertEqual(note.files[0].filename, "note.m4a")
        XCTAssertEqual(note.files[0].name, "file")

        // Khong ghi am thi van la note anh nhu truoc.
        var photo = note
        photo.audio = nil
        XCTAssertEqual(photo.type, "photo")
    }

    /// Worker chi tra counts/moods — total, chuoi ngay, mood hay gap tinh o day.
    /// Huong keo tu nut noi -> loai note. Vung chet phai la "viet chu", khong
    /// phai huy: bam nhanh la mo o go chu.
    /// Moi mood trong whitelist phai co mat tu ve — thieu la Canvas ve ra o trong.
    func testEveryMoodHasFace() {
        for mood in moods.map(\.emoji) {
            XCTAssertNotNil(moodFaceSpec(mood), mood)
        }
        XCTAssertNil(moodFaceSpec("🤖"))
        XCTAssertNil(moodFaceSpec(""))
    }

    func testFabIntent() {
        XCTAssertEqual(fabIntent(for: .zero), .open(.blank))
        XCTAssertEqual(fabIntent(for: CGSize(width: 10, height: -20)), .open(.blank))
        XCTAssertEqual(fabIntent(for: CGSize(width: 0, height: -80)), .open(.record))
        XCTAssertEqual(fabIntent(for: CGSize(width: -80, height: 0)), .open(.blank))
        XCTAssertEqual(fabIntent(for: CGSize(width: 80, height: 0)), .open(.camera))
        XCTAssertEqual(fabIntent(for: CGSize(width: 0, height: 80)), .cancel)
        // Cheo: truc lech nhieu hon quyet dinh.
        XCTAssertEqual(fabIntent(for: CGSize(width: 50, height: -90)), .open(.record))
        XCTAssertEqual(fabIntent(for: CGSize(width: 90, height: -50)), .open(.camera))
    }

    func testShiftDay() {
        XCTAssertEqual(shiftDay("2026-09-01", by: -1), "2026-08-31")
        XCTAssertEqual(shiftDay("2026-12-31", by: 1), "2027-01-01")
        XCTAssertEqual(shiftDay("2028-02-28", by: 1), "2028-02-29")   // nam nhuan
        XCTAssertEqual(shiftDay("hong", by: 1), "hong")
    }

    func testYearSummary() {
        let counts = ["2026-01-01": 2, "2026-01-02": 1, "2026-01-03": 1,
                      "2026-03-10": 1, "2026-12-31": 3]
        let moods = ["2026-01-01": "😄", "2026-01-02": "😄", "2026-03-10": "😔"]
        let s = yearSummary(counts: counts, moods: moods)
        XCTAssertEqual(s.total, 8)
        XCTAssertEqual(s.days, 5)
        XCTAssertEqual(s.longestStreak, 3)      // 01-01 -> 01-03
        XCTAssertEqual(s.topMood, "😄")

        let empty = yearSummary(counts: [:], moods: [:])
        XCTAssertEqual(empty.total, 0)
        XCTAssertEqual(empty.longestStreak, 0)
        XCTAssertNil(empty.topMood)

        // Chuoi vat qua thang: 31/1 -> 1/2 la lien tiep.
        let cross = yearSummary(counts: ["2026-01-31": 1, "2026-02-01": 1], moods: [:])
        XCTAssertEqual(cross.longestStreak, 2)
    }

    func testDaysInMonth() {
        XCTAssertEqual(daysIn(year: 2026, month: 2), 28)
        XCTAssertEqual(daysIn(year: 2028, month: 2), 29)   // nam nhuan
        XCTAssertEqual(daysIn(year: 2026, month: 12), 31)
    }

    func testMultipartBodyShape() {
        let form = MultipartForm(fields: [("date", "2026-09-01")],
                                 files: [.init(name: "file", filename: "a.jpg",
                                               mime: "image/jpeg", data: Data("fake-jpeg".utf8))])
        let body = String(data: form.body, encoding: .utf8)!
        XCTAssertTrue(body.contains("--\(form.boundary)\r\nContent-Disposition: form-data; name=\"date\"\r\n\r\n2026-09-01\r\n"))
        XCTAssertTrue(body.contains("filename=\"a.jpg\""))
        XCTAssertTrue(body.hasSuffix("--\(form.boundary)--\r\n"))
        XCTAssertEqual(form.contentType, "multipart/form-data; boundary=\(form.boundary)")
    }

    /// Bo mood phai khop dung whitelist cua worker, gui khac la bi bo im lang.
    func testMoodsMatchServerWhitelist() {
        XCTAssertEqual(moods.map(\.emoji), ["😄", "🙂", "😐", "😔", "😡", "😴", "🥳", "😰"])
    }

    func testNoteTypeLabels() {
        XCTAssertEqual(noteTypeIcon("photo"), "photo")
        XCTAssertEqual(noteTypeIcon("loai-moi"), "text.alignleft")
        XCTAssertEqual(noteTypeLabel("audio"), "Ghi âm")
        XCTAssertEqual(noteTypeLabel("loai-moi"), "Chữ")
    }
}
