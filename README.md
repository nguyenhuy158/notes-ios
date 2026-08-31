# Notes iOS

App iOS native (SwiftUI) cho nhật ký [notes.huyab.click](https://notes.huyab.click).
Không dùng thư viện ngoài — chỉ SwiftUI + Foundation + WebKit.

## Làm được gì

- Đăng nhập bằng SSO Google dùng chung của huyab.click
- Xem theo tháng → theo ngày, ghim / sửa chữ / sửa mood / xoá (xoá mềm)
- Viết note mới: chữ, mood, địa điểm, nhãn, tối đa 10 ảnh chụp tại chỗ
- Ghi âm → tự ra chữ: app ghi m4a 16kHz mono rồi POST `type=audio` với chữ để
  trống; worker chạy Whisper (`@cf/openai/whisper`) và điền text. **Không nhúng
  Whisper vào app** — model 100MB+ trên máy là vô nghĩa khi server đã làm sẵn.
- Nhãn: đếm số note theo nhãn, đổi tên nhãn, xem note theo nhãn
- Album ảnh theo tháng (lấy `/api/export?format=json` rồi lọc ở máy — worker
  không có endpoint "ảnh theo tháng")
- Tổng kết năm: lưới 12 tháng theo mật độ note + tổng note / số ngày ghi /
  chuỗi ngày dài nhất / mood hay gặp (tính ở client từ `/api/year`)
- Thùng rác: hoàn lại hoặc xoá hẳn
- Cài đặt: tài khoản, số note, dung lượng media

Để lại cho web: link chia sẻ, khoá PIN, hàng chờ offline, quay video, xuất dữ liệu,
in album ra PDF.

## Vì sao login bằng WKWebView

SSO chỉ nhận `redirect_uri` https trong huyab.click, nên `ASWebAuthenticationSession`
với custom scheme không dùng được. App mở `WKWebView`, sau khi về
`notes.huyab.click` thì đọc cookie `huyab_sso` (HttpOnly) từ `WKHTTPCookieStore`
rồi lưu vào Keychain.

**Quan trọng:** worker của notes chỉ xác thực bằng **cookie**, không đọc
`Authorization: Bearer`. Nên `ApiClient` tự set header `Cookie: huyab_sso=…` và
tắt cookie jar của URLSession (`httpShouldHandleCookies = false`) để cookie cũ
không ghi đè.

## Build

```bash
xcodebuild -scheme Notes -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 11,OS=17.5' \
  -derivedDataPath build/dd test      # 27 test
open Notes.xcodeproj                  # hoặc chạy bằng Xcode
```

## Cài lên máy thật

```bash
./make-ipa.sh          # -> build/Notes.ipa (chưa ký)
open -a Sideloadly build/Notes.ipa
```

Trong Sideloadly: chọn iPhone, nhập Apple ID, Start. Xong thì vào
Settings → General → VPN & Device Management để tin cert. Apple ID miễn phí thì
7 ngày phải sign lại — token nằm trong Keychain nên không phải login lại.
