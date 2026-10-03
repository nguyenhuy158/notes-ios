# Repository Guidelines

## Project Structure & Module Organization

Notes iOS is a native SwiftUI client for the notes journal at notes.huyab.click:
month/day browsing, compose (text, mood, location, tags, photos, voice-to-text
via the worker's Whisper), tags, photo album, year summary, trash and settings.
Share links, PIN lock, offline queue, video, export and PDF stay on the web.

It follows the shared SwiftUI template used by the `*-ios` repos (chia-keo-ios,
notes-ios, monitor-ios): zero dependencies (no SPM, no CocoaPods), one app
target plus one XCTest target, and the same `Auth.swift` / `API.swift` /
`LoginView.swift` / `make-ipa.sh` layout.

- **Auth** (`Auth.swift`, `LoginView.swift`): the shared SSO at
  `auth.huyab.click` only accepts https `redirect_uri` values inside
  `huyab.click`, so `ASWebAuthenticationSession` with a custom scheme cannot be
  used. `LoginView` opens a `WKWebView`; once it lands back on
  `notes.huyab.click`, `WKHTTPCookieStore` reads the HttpOnly `huyab_sso` cookie
  and the JWT is stored in the Keychain. `SsoToken` never verifies the signature
  (the server does); it only reads `exp` to know when to stop calling the API.
- **API** (`API.swift`): DTOs are a projection of `src/api.ts` in the notes web
  repo. Declare only fields the app actually uses — Codable ignores unknown
  keys, so new server fields never break the app. `ApiClient` targets
  `https://notes.huyab.click` and authenticates with a `Cookie: huyab_sso=<jwt>`
  header with the URLSession cookie jar disabled (`httpShouldHandleCookies =
  false`) — the notes worker authenticates by cookie only and does NOT read
  `Authorization: Bearer`. Tests inject a `URLSession` with a fake
  `URLProtocol`; the app uses `URLSession.shared`.

Folder structure:

```text
Notes/                      # App target sources (SwiftUI, iOS 16+)
  NotesApp.swift            #   `@main` app entry; `AuthStore` switches `LoginView` / `RootTabs`
  Auth.swift                #   `SsoToken` (reads JWT `exp` only), `Keychain`, `AuthStore`
  LoginView.swift           #   WKWebView SSO login via auth.huyab.click, `WebSessionCleaner`
  API.swift                 #   Decodable DTOs + `ApiClient` (URLSession, Cookie auth)
  DaysView.swift            #   `RootTabs`, month/day list
  DayView.swift             #   Day view, `NoteCard`, `MoodPicker`, `RemoteImage` + `ImageCache`
  ComposeView.swift         #   Compose note, tag parsing, `ImagePicker`, `AudioRecorder` (m4a 16kHz mono)
  ExtrasView.swift          #   Tags, notes by tag, album, year summary
  SettingsView.swift        #   Settings + trash
  MoodFace.swift            #   Mood face drawing spec + view
  Assets.xcassets/          #   AppIcon + AppIconPreview
NotesTests/                 # XCTest unit target (@testable import Notes)
  ApiClientTests.swift      #   `ApiClient` against `StubProtocol` (method/header/body/errors)
  DecodingTests.swift       #   DTO decoding from server JSON fixtures
  LogicTests.swift          #   Pure logic: token expiry, day/month shifting, formatters, tag limits, moods, multipart body, year summary
Notes.xcodeproj/            # Hand-maintained project, shared scheme `Notes`
make-ipa.sh                 # Unsigned Release build -> build/Notes.ipa (Sideloadly signs)
.github/workflows/test.yml  # CI: xcodebuild test + coverage on macos-15
.swiftlint.yml              # Optional local SwiftLint config (not in CI)
build/                      # Local derived data + .ipa output (gitignored)
```

The `.xcodeproj` uses classic groups (not synchronized folders): every new
`.swift` file must be registered in `project.pbxproj` (file reference, build
file, group and the target's Sources phase), otherwise it is silently not
compiled.

## Build, Test, and Development Commands

- `open Notes.xcodeproj`: open in Xcode; Cmd-R runs on the simulator.
- `xcodebuild -project Notes.xcodeproj -scheme Notes -sdk iphonesimulator build`:
  simulator build.
- `xcodebuild test -project Notes.xcodeproj -scheme Notes -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 11' -derivedDataPath build/dd`:
  run the XCTest suite (pick any installed iPhone simulator; CI picks one at
  runtime).
- `./make-ipa.sh`: unsigned Release build packaged as `build/Notes.ipa`; drag it
  into Sideloadly to sign with a free Apple ID (re-sign every 7 days; the
  Keychain token survives re-signing). Build log: `/tmp/notes-build.log`.
- `swiftlint`: optional local lint using `.swiftlint.yml` (not run in CI).

Local toolchain is Xcode 15.4; CI runs on `macos-15`.

## Coding Style & Naming Conventions

Swift 5, SwiftUI, deployment target iOS 16.0, iPhone only. Use only system
frameworks (SwiftUI, Foundation, AVFoundation and WebKit); do not add
third-party dependencies. Four-space indentation. Types and SwiftUI views in
PascalCase (`HomeView`, `ApiClient`), server DTOs mostly prefixed with `Api`.
Code comments are Vietnamese without diacritics; user-facing strings are
Vietnamese with diacritics. Keep business logic on the server; put pure,
testable helpers in free functions or small types beside the view that uses
them. No magic strings/numbers: name them as constants (e.g. `ApiClient.origin`,
`ssoOrigin`, `appHost`).

## Testing Guidelines

Tests use XCTest in `NotesTests/` with `@testable import Notes`. Never hit the
real network: `ApiClientTests` uses `StubProtocol` on a dedicated `URLSession`.
When adding an endpoint, add a decoding fixture in `DecodingTests` and a
request-shape test in `ApiClientTests`. CI (`.github/workflows/test.yml`) runs
`xcodebuild test` with code coverage and must be green before merging.

Logic checks live only in XCTest (there is no DEBUG startup self-check). There is
no browser e2e: this is a native app with no web surface.

## Commit & Pull Request Guidelines

Use concise Conventional Commits; existing history uses short Vietnamese
subjects without diacritics, e.g. `feat: app iOS cho notes.huyab.click`. Pull
requests should include a short summary, `xcodebuild test` results, and
simulator screenshots for visible UI changes.

## Agent-Specific Instructions

Keep responses short and focused. If a requirement is unclear, ask before making
assumptions. Keep the app phone-scoped: share links, PIN lock, offline queue,
video capture, export and PDF printing stay on notes.huyab.click. Do not embed
Whisper or other models; transcription is done by the worker (`type=audio` with
empty text). When the server contract changes, update the DTOs here and the
server repo together. Do not commit `build/`, `.ipa` files or `xcuserdata/`.
