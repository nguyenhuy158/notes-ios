import SwiftUI
import WebKit

private let ssoOrigin = "https://auth.huyab.click"
private let appHost = "notes.huyab.click"
private let cookieName = "huyab_sso"

/// Don cookie trong jar cua WKWebView khi dang xuat. Khong don thi lan sau bam
/// dang nhap la SSO tra ve ngay account cu, khong doi nguoi duoc.
enum WebSessionCleaner {
    static func clear() {
        let store = WKWebsiteDataStore.default()
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                             for: records.filter { $0.displayName.contains("huyab") }) {}
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var showingWeb = false
    @State private var webError: String?
    @State private var online = true

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image("AppIconPreview")
                .resizable()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.quaternary)
                )

            VStack(spacing: 4) {
                Text("Notes").font(.largeTitle.bold())
                Text("Nhật ký hàng ngày")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let message = webError ?? auth.notice {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                webError = nil
                showingWeb = true
            } label: {
                HStack(spacing: 10) {
                    Text("G").font(.title3.weight(.bold)).foregroundStyle(.blue)
                    Text("Tiếp tục với Google").fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.quaternary)
                )
            }
            .buttonStyle(.plain)
            .disabled(!online)

            Text(online ? "Đăng nhập qua auth.huyab.click" : "Không có mạng")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .sheet(isPresented: $showingWeb) {
            LoginWebSheet(
                onToken: { token in
                    showingWeb = false
                    auth.signIn(token: token)
                },
                onFailure: { message in
                    showingWeb = false
                    webError = message
                }
            )
        }
        .task { online = await hasNetwork() }
    }
}

/// Kiem tra mang bang mot HEAD toi chinh server thay vi NWPathMonitor: "co
/// wifi" khong dong nghia goi duoc API, va day la cai app that su can biet.
/// `/api/version` la route duy nhat khong doi dang nhap.
private func hasNetwork() async -> Bool {
    var req = URLRequest(url: URL(string: ApiClient.origin + "/api/version")!)
    req.httpMethod = "HEAD"
    req.timeoutInterval = 5
    return (try? await URLSession.shared.data(for: req)) != nil
}

/// Vi sao WKWebView chu khong phai ASWebAuthenticationSession: SSO chi nhan
/// `redirect_uri` la https trong huyab.click, khong nhan custom scheme, nen
/// khong co callback nao de bat. Bu lai WKHTTPCookieStore doc duoc cookie
/// HttpOnly — dung thu JavaScript khong voi tay tới được.
private struct LoginWebSheet: View {
    let onToken: (String) -> Void
    let onFailure: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var host = "auth.huyab.click"

    var body: some View {
        NavigationStack {
            LoginWebView(host: $host, onToken: onToken, onFailure: onFailure)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(host)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Huỷ") { dismiss() }
                    }
                }
        }
    }
}

private struct LoginWebView: UIViewRepresentable {
    @Binding var host: String
    let onToken: (String) -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(host: $host, onToken: onToken, onFailure: onFailure)
    }

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.navigationDelegate = context.coordinator

        var components = URLComponents(string: ssoOrigin + "/login")!
        // Quay ve chinh app web: SSO chi chap nhan redirect trong huyab.click.
        components.queryItems = [URLQueryItem(name: "redirect_uri", value: ApiClient.origin + "/")]
        view.load(URLRequest(url: components.url!))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var host: String
        let onToken: (String) -> Void
        let onFailure: (String) -> Void
        /// Chan goi onToken/onFailure hai lan: mot trang co the finish nhieu nhip.
        private var settled = false

        init(host: Binding<String>, onToken: @escaping (String) -> Void, onFailure: @escaping (String) -> Void) {
            _host = host
            self.onToken = onToken
            self.onFailure = onFailure
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let current = webView.url?.host ?? ""
            host = current
            guard !settled, current == appHost else { return }

            // Da ve tren app web nghia la SSO da set cookie xong. Doc ra roi thoi.
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.settled else { return }
                self.settled = true

                guard let token = cookies.first(where: { $0.name == cookieName })?.value else {
                    // Ve dung domain ma khong co cookie: dung treo sheet mai mai.
                    self.onFailure("Đăng nhập xong nhưng không nhận được phiên. Thử lại.")
                    return
                }
                guard SsoToken.isUsable(token) else {
                    self.onFailure("Phiên nhận được đã hết hạn.")
                    return
                }
                self.onToken(token)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }

        private func fail(_ error: Error) {
            guard !settled, (error as NSError).code != NSURLErrorCancelled else { return }
            settled = true
            onFailure(error.localizedDescription)
        }
    }
}
