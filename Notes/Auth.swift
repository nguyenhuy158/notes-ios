import Foundation

/// Token la JWT RS256 do auth.huyab.click ky. App KHONG verify chu ky — khong co
/// public key va cung khong can: worker verify moi request bang JWKS. App chi
/// doc `exp` de biet khi nao khoi goi API, tranh mot vong 401 chac chan that bai.
enum SsoToken {
    /// Han cua token, hoac nil neu payload khong doc duoc.
    static func expiry(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count == 3, let payload = base64UrlDecode(String(parts[1])) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let exp = json["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    /// Con han them it nhat `slack` giay. Bien do de khong dang nhap giua
    /// duong khi token chet ngay sau man hinh dau tien.
    static func isUsable(_ token: String, slack: TimeInterval = 60) -> Bool {
        guard let expiry = expiry(token) else { return false }
        return expiry.timeIntervalSinceNow > slack
    }

    static func base64UrlDecode(_ part: String) -> Data? {
        var s = part.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        s += String(repeating: "=", count: (4 - s.count % 4) % 4)
        return Data(base64Encoded: s)
    }
}

/// Luu token trong Keychain chu khong UserDefaults: day la thong tin dang nhap,
/// va Keychain con nguyen khi app bi re-sign moi 7 ngay boi Sideloadly.
enum Keychain {
    private static let service = "click.huyab.notes"
    private static let account = "sso-token"

    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read() -> String? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String) {
        SecItemDelete(base as CFDictionary)
        var item = base
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    static func clear() {
        SecItemDelete(base as CFDictionary)
    }
}

@MainActor
final class AuthStore: ObservableObject {
    /// nil = chua dang nhap. Moi view doc day de biet ve man hinh nao.
    @Published private(set) var token: String?
    /// Hien duoi nut Google sau khi bi dang xuat vi token het han.
    @Published var notice: String?

    init() {
        if let saved = Keychain.read(), SsoToken.isUsable(saved) {
            token = saved
        } else {
            // Token rac hoac het han: don luon cho lan sau khong phai doc lai.
            Keychain.clear()
        }
    }

    func signIn(token newToken: String) {
        Keychain.write(newToken)
        token = newToken
        notice = nil
    }

    func signOut(notice message: String? = nil) {
        Keychain.clear()
        // Xoa ca cookie trong jar cua WKWebView, khong thi lan sau bam dang
        // nhap la SSO tra ve ngay chinh account cu, doi nguoi khong duoc.
        WebSessionCleaner.clear()
        token = nil
        notice = message
    }

    var client: ApiClient? { token.map { ApiClient(token: $0) } }
}

extension AuthStore {
    /// Vo mot loi goi API: 401 thi dang xuat luon, loi khac tra ve chuoi de
    /// man hinh hien. Moi man hinh deu can dung mot xu ly nay.
    func perform(_ body: (ApiClient) async throws -> Void) async -> String? {
        guard let client else { return nil }
        do {
            try await body(client)
            return nil
        } catch ApiError.unauthorized {
            signOut(notice: "Phiên đã hết hạn, đăng nhập lại nhé.")
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
