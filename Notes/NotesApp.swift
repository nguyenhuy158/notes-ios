import SwiftUI

@main
struct NotesApp: App {
    @StateObject private var auth = AuthStore()

    init() {
        #if DEBUG
        selfCheck()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            // Mot cong duy nhat: co token thi vao app, khong thi man dang nhap.
            // Moi view goi auth.signOut() khi gap 401 nen het han la tu quay ve day.
            if auth.token == nil {
                LoginView().environmentObject(auth)
            } else {
                RootTabs().environmentObject(auth)
            }
        }
    }
}

#if DEBUG
/// Kiem tra nhanh may cho de sai am tham: doc `exp` cua JWT, dung multipart,
/// va lui thang qua ranh nam. Chay luc khoi dong ban Debug — sai la crash ngay.
private func selfCheck() {
    // {"exp":2000000000} base64url, khong padding — dung dang SSO tra ve.
    let payload = "eyJleHAiOjIwMDAwMDAwMDB9"
    assert(SsoToken.expiry("header.\(payload).sig") == Date(timeIntervalSince1970: 2_000_000_000))
    assert(SsoToken.isUsable("header.\(payload).sig"))

    // {"exp":1000000000} — nam 2001, chac chan het han.
    assert(!SsoToken.isUsable("header.eyJleHAiOjEwMDAwMDAwMDB9.sig"))
    assert(!SsoToken.isUsable("khong-phai-jwt"))
    assert(SsoToken.expiry("a.b.c") == nil)

    assert(shiftMonth("2026-01", by: -1) == "2025-12")
    assert(shiftMonth("2026-12", by: 1) == "2027-01")
    assert(formatMonthTitle("2026-09") == "Tháng 9, 2026")
    assert(formatBytes(0) == "0 B")
    assert(formatBytes(1536) == "1.5 KB")

    // Note co anh phai la type=photo va mang theo dung so file.
    let photo = NewNote(date: "2026-09-01", text: "hi", mood: "😄", location: "",
                        tags: ["a", "b"], photos: [Data([1, 2, 3]), Data([4])])
    assert(photo.fields.contains { $0 == ("type", "photo") })
    assert(photo.fields.contains { $0 == ("tags", "a,b") })
    assert(photo.files.count == 2)

    let text = NewNote(date: "2026-09-01", text: "hi", mood: nil, location: "",
                       tags: [], photos: [])
    assert(text.fields.contains { $0 == ("type", "text") })
    assert(!text.fields.contains { $0.0 == "mood" })

    let form = MultipartForm(fields: [("date", "2026-09-01")], files: photo.files)
    let body = String(data: form.body, encoding: .utf8) ?? ""
    assert(body.contains("name=\"date\""))
    assert(body.contains("filename=\"photo-1.jpg\""))
    assert(body.hasSuffix("--\(form.boundary)--\r\n"))
}
#endif
