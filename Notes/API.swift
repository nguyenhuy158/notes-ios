import Foundation

// Cac struct duoi day la ban chieu cua src/api.ts ben notes. Chi khai bao field
// app THAT SU dung — Codable bo qua field la, nen server them field moi khong
// lam app vo.

struct ApiNote: Decodable, Identifiable {
    let id: String
    let date: String
    /// "text" | "audio" | "photo" | "video".
    let type: String
    /// Voi note text la noi dung; voi media la caption (co the rong).
    let text: String
    let mood: String?
    let pinned: Bool
    let tags: [String]
    let location: String?
    /// Duong dan tuong doi kieu "/api/media/<id>?v=..." — phai kem cookie moi tai duoc.
    let mediaUrl: String?
    let mediaUrls: [String]
    let createdAt: String
}

struct NotesResponse: Decodable {
    let notes: [ApiNote]
}

struct NoteResponse: Decodable {
    let note: ApiNote
}

/// GET /api/days?month=YYYY-MM. Key la ngay "YYYY-MM-DD".
struct DaysResponse: Decodable {
    let days: [String: [String]]
    let moods: [String: String]
    let tags: [String: [String]]
}

struct MeResponse: Decodable {
    let email: String
    let name: String
}

struct TagCount: Decodable, Identifiable {
    let tag: String
    let count: Int
    var id: String { tag }
}

struct TagsResponse: Decodable {
    let tags: [TagCount]
}

struct YearResponse: Decodable {
    /// "2026-09-01" -> so note; mood dai dien cua ngay do.
    let counts: [String: Int]
    let moods: [String: String]
}

struct ExportResponse: Decodable {
    let notes: [ApiNote]
}

struct RenameTagInput: Encodable {
    let from: String
    let to: String
}

struct RenameTagResponse: Decodable {
    let updated: Int
}

/// Tong ket nam tinh o client tu /api/year (worker chi tra counts + moods).
struct YearSummary {
    let total: Int
    let days: Int
    let topMood: String?
    let longestStreak: Int
}

func yearSummary(counts: [String: Int], moods: [String: String]) -> YearSummary {
    let total = counts.values.reduce(0, +)
    let topMood = Dictionary(grouping: moods.values, by: { $0 })
        .max { a, b in
            // Bang phieu thi lay emoji nho hon de ket qua on dinh giua cac lan mo.
            (a.value.count, b.key) < (b.value.count, a.key)
        }?.key

    // Chuoi ngay lien tiep co note: sort chuoi "yyyy-MM-dd" la sort theo ngay.
    var longest = 0
    var current = 0
    var previous: Date?
    for day in counts.keys.sorted() {
        guard let date = parseDay(day) else { continue }
        if let previous, Calendar.current.dateComponents([.day], from: previous, to: date).day == 1 {
            current += 1
        } else {
            current = 1
        }
        previous = date
        longest = max(longest, current)
    }

    return YearSummary(total: total, days: counts.count, topMood: topMood, longestStreak: longest)
}

struct StatsResponse: Decodable {
    let noteCount: Int
    let mediaBytes: Int
}

struct TextInput: Encodable {
    var text: String
}

struct MoodInput: Encodable {
    /// nil = bo mood. Encoder mac dinh bo han field khi nil, ma worker doc
    /// `"mood" in body` — bo han thi thanh "khong doi". Phai ghi null tay.
    var mood: String?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mood, forKey: .mood)
    }

    enum CodingKeys: String, CodingKey { case mood }
}

struct PinInput: Encodable {
    var pinned: Bool
}

enum ApiError: LocalizedError {
    /// Token het han hoac bi thu hoi — goi AuthStore.signOut, dung retry.
    case unauthorized
    case status(Int)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: "Phiên đã hết hạn"
        case .status(let code): "Máy chủ trả lỗi \(code)"
        case .transport(let message): message
        }
    }
}

struct ApiClient {
    static let origin = "https://notes.huyab.click"

    let token: String
    /// Test tiem URLSession co URLProtocol gia vao day; app dung shared.
    var session: URLSession = .shared

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await send(request(path, method: "GET"))
    }

    func put<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        try await send(json(path, method: "PUT", body: body))
    }

    /// Endpoint chi doi trang thai (delete, restore, purge...) — bo qua body tra ve.
    func fire(_ path: String, method: String) async throws {
        _ = try await send(request(path, method: method)) as Ignored
    }

    /// POST /api/notes: worker doc multipart (`c.req.parseBody`), khong phai JSON.
    func createNote(_ note: NewNote) async throws -> ApiNote {
        var req = request("/api/notes", method: "POST")
        let form = MultipartForm(fields: note.fields, files: note.files)
        req.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = form.body
        let response: NoteResponse = try await send(req)
        return response.note
    }

    /// Anh/audio cua note. Tra byte tho vi AsyncImage khong gan duoc cookie.
    func media(_ path: String) async throws -> Data {
        let req = request(path, method: "GET")
        do {
            let (data, response) = try await session.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 { throw ApiError.unauthorized }
            guard (200..<300).contains(code) else { throw ApiError.status(code) }
            return data
        } catch let error as ApiError {
            throw error
        } catch {
            throw ApiError.transport(error.localizedDescription)
        }
    }

    private func json(_ path: String, method: String, body: some Encodable) throws -> URLRequest {
        var req = request(path, method: method)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        return req
    }

    private func request(_ path: String, method: String) -> URLRequest {
        var req = URLRequest(url: URL(string: Self.origin + path)!)
        req.httpMethod = method
        // Cookie chu khong phai `Authorization: Bearer`: worker cua notes doc
        // duy nhat cookie `huyab_sso` (worker/src/session.js getClaimsFromRequest).
        // Tu dat header va tat cookie jar de jar khong chen ngang mot cookie cu.
        req.setValue("huyab_sso=\(token)", forHTTPHeaderField: "Cookie")
        req.httpShouldHandleCookies = false
        return req
    }

    /// Nuot moi thu, ke ca body rong — dung cho request chi can biet 2xx.
    struct Ignored: Decodable {
        init() {}
        init(from decoder: Decoder) throws {}
    }

    private func send<T: Decodable>(_ req: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw ApiError.transport(error.localizedDescription)
        }

        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw ApiError.unauthorized }
        guard (200..<300).contains(code) else { throw ApiError.status(code) }

        if T.self == Ignored.self { return Ignored() as! T }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            #if DEBUG
            throw ApiError.transport("Không đọc được dữ liệu: \(error)")
            #else
            throw ApiError.transport("Dữ liệu trả về không đọc được")
            #endif
        }
    }
}

// MARK: - Note moi

/// Mot note sap gui len. `photos` rong = note text; co anh = note photo, chu
/// `text` thanh caption (worker cho phep caption rong voi note media).
struct NewNote {
    var date: String
    var text: String
    var mood: String?
    var location: String
    var tags: [String]
    var photos: [Data]
    /// Ghi am m4a. Co audio thi la note "audio" — worker chi nhan 1 file cho
    /// loai nay nen khong tron voi anh duoc.
    var audio: Data?

    var isPhoto: Bool { audio == nil && !photos.isEmpty }

    /// Note audio khong tu go chu -> worker chay Whisper (@cf/openai/whisper)
    /// va dien text ho. Nen chu o day de rong la co y.
    var type: String {
        if audio != nil { return "audio" }
        return isPhoto ? "photo" : "text"
    }

    var fields: [(String, String)] {
        var out = [("date", date), ("type", type), ("text", text)]
        if let mood, !mood.isEmpty { out.append(("mood", mood)) }
        if !location.isEmpty { out.append(("location", location)) }
        if !tags.isEmpty { out.append(("tags", tags.joined(separator: ","))) }
        return out
    }

    var files: [MultipartForm.File] {
        if let audio {
            return [.init(name: "file", filename: "note.m4a", mime: "audio/mp4", data: audio)]
        }
        return photos.enumerated().map { index, data in
            // Cung ten field "file" cho moi anh: worker parseBody({ all: true })
            // gom lai thanh gallery, slot 0 la anh chinh.
            .init(name: "file", filename: "photo-\(index).jpg", mime: "image/jpeg", data: data)
        }
    }
}

/// Multipart/form-data toi gian. URLSession khong co san, ma day la dinh dang
/// duy nhat POST /api/notes nhan.
struct MultipartForm {
    struct File {
        let name: String
        let filename: String
        let mime: String
        let data: Data
    }

    let boundary = "notes-ios-\(UUID().uuidString)"
    let fields: [(String, String)]
    let files: [File]

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    var body: Data {
        var out = Data()
        for (name, value) in fields {
            out.append("--\(boundary)\r\n")
            out.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            out.append(value)
            out.append("\r\n")
        }
        for file in files {
            out.append("--\(boundary)\r\n")
            out.append("Content-Disposition: form-data; name=\"\(file.name)\"; filename=\"\(file.filename)\"\r\n")
            out.append("Content-Type: \(file.mime)\r\n\r\n")
            out.append(file.data)
            out.append("\r\n")
        }
        out.append("--\(boundary)--\r\n")
        return out
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}

// MARK: - Nhan tieng Viet

/// Dung bo mood cua worker (`MOODS` trong worker/src/index.ts). Server chi nhan
/// dung 8 ky tu nay, gui khac la bi bo im lang.
let moods: [(emoji: String, label: String)] = [
    ("😄", "Vui"),
    ("🙂", "Ổn"),
    ("😐", "Bình thường"),
    ("😔", "Buồn"),
    ("😡", "Tức"),
    ("😴", "Buồn ngủ"),
    ("🥳", "Ăn mừng"),
    ("😰", "Lo lắng"),
]

/// Icon SF Symbols cho tung loai note.
func noteTypeIcon(_ type: String) -> String {
    switch type {
    case "photo": "photo"
    case "audio": "waveform"
    case "video": "video"
    default: "text.alignleft"
    }
}

func noteTypeLabel(_ type: String) -> String {
    switch type {
    case "photo": "Ảnh"
    case "audio": "Ghi âm"
    case "video": "Video"
    default: "Chữ"
    }
}

/// "2026-09-01" -> "Thứ ba, 1 thg 9". Chuoi la tra ve nguyen ban chu khong bo
/// trong — thay chuoi la con de doan hon la thay o trong.
func formatDayTitle(_ date: String) -> String {
    guard let parsed = parseDay(date) else { return date }
    let out = DateFormatter()
    out.locale = Locale(identifier: "vi_VN")
    out.setLocalizedDateFormatFromTemplate("EEEE, d MMM")
    return out.string(from: parsed).capitalizedFirst
}

/// "2026-09" -> "Tháng 9, 2026".
func formatMonthTitle(_ month: String) -> String {
    let parts = month.split(separator: "-")
    guard parts.count == 2, let m = Int(parts[1]) else { return month }
    return "Tháng \(m), \(parts[0])"
}

/// Gio tao note, "19:30". Ngay da nam o tieu de nhom nen khong lap lai.
func formatTime(_ iso: String) -> String {
    guard let date = parseIso(iso) else { return iso }
    let out = DateFormatter()
    out.locale = Locale(identifier: "vi_VN")
    out.setLocalizedDateFormatFromTemplate("HH:mm")
    return out.string(from: date)
}

/// "1.2 MB". Dung o Cai dat de biet R2 dang giu bao nhieu.
func formatBytes(_ bytes: Int) -> String {
    let units = ["B", "KB", "MB", "GB"]
    var value = Double(bytes)
    var unit = 0
    while value >= 1024, unit < units.count - 1 {
        value /= 1024
        unit += 1
    }
    return unit == 0 ? "\(bytes) B" : String(format: "%.1f %@", value, units[unit])
}

// MARK: - Ngay thang

/// Lich Gregorian, mui gio may. Ngay trong notes la ngay dia phuong nguoi viet
/// nhin thay tren lich, khong phai UTC.
private let dayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

func parseDay(_ date: String) -> Date? {
    dayFormatter.date(from: date)
}

func dayString(_ date: Date) -> String {
    dayFormatter.string(from: date)
}

/// Ngay truoc/sau cua "yyyy-MM-dd". Calendar lo chuyen thang/nam nhuan.
func shiftDay(_ day: String, by days: Int) -> String {
    guard let date = parseDay(day),
          let moved = Calendar.current.date(byAdding: .day, value: days, to: date)
    else { return day }
    return dayString(moved)
}

func monthString(_ date: Date) -> String {
    String(dayString(date).prefix(7))
}

/// Thang truoc/sau cua "YYYY-MM". Tinh bang Calendar chu khong tu tru 1 vao
/// so thang — thang 1 lui mot nhip la sang nam truoc.
func shiftMonth(_ month: String, by delta: Int) -> String {
    guard let date = parseDay(month + "-01"),
          let shifted = Calendar(identifier: .gregorian).date(byAdding: .month, value: delta, to: date)
    else { return month }
    return monthString(shifted)
}

func parseIso(_ iso: String) -> Date? {
    let parsers = [ISO8601DateFormatter(), {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()]
    if let date = parsers.lazy.compactMap({ $0.date(from: iso) }).first { return date }
    // D1 luu created_at dang "2026-09-01 12:30:00" (khong co chu T, khong mui gio).
    let sqlite = DateFormatter()
    sqlite.locale = Locale(identifier: "en_US_POSIX")
    sqlite.timeZone = TimeZone(identifier: "UTC")
    sqlite.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return sqlite.date(from: iso)
}

extension String {
    /// "thứ ba, 1 thg 9" -> "Thứ ba, 1 thg 9". Locale vi cho ra chu thuong.
    var capitalizedFirst: String {
        isEmpty ? self : prefix(1).uppercased() + dropFirst()
    }
}
