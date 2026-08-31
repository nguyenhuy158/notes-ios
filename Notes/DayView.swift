import SwiftUI
import AVFoundation

/// Mot ngay: het note trong ngay, ghim truoc (server da sort san). Sua chu,
/// doi mood, ghim, xoa mem — dung nhung viec lam tren dien thoai duoc.
struct DayView: View {
    let date: String

    /// Ngay dang xem = date + offset. TabView kieu page cho truot trai/phai
    /// doi ngay; +-365 la du xa cho viec luot bang tay.
    @State private var offset = 0
    @State private var composing: ComposeStart?
    @State private var reload = 0

    private var current: String { shiftDay(date, by: offset) }

    var body: some View {
        TabView(selection: $offset) {
            ForEach(-365...365, id: \.self) { day in
                DayNotes(date: shiftDay(date, by: day), reload: reload)
                    .tag(day)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .navigationTitle(formatDayTitle(current))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button { composing = .blank } label: { Label("Ghi chú mới", systemImage: "plus") }
        }
        // Ghi nhanh: chon ghi am / chup anh / viet chu cho ngay dang xem.
        .overlay(alignment: .bottomTrailing) { RecordFab { composing = $0 } }
        .sheet(item: $composing) { start in
            ComposeView(date: current, start: start) { reload += 1 }
        }
    }
}

/// Note cua dung mot ngay. Tach ra khoi DayView de moi trang trong TabView co
/// state rieng — khong thi truot qua lai se thay note cua ngay cu.
private struct DayNotes: View {
    let date: String
    /// Doi so nay = tai lai (sau khi viet note moi tu DayView).
    let reload: Int

    @EnvironmentObject private var auth: AuthStore
    @State private var notes: [ApiNote] = []
    @State private var error: String?
    @State private var loading = true
    @State private var editing: ApiNote?

    var body: some View {
        List {
            if let error {
                Text(error).foregroundStyle(.red).font(.footnote)
            }

            ForEach(notes) { note in
                NoteCard(note: note)
                    .swipeActions(edge: .leading) {
                        Button {
                            Task { await pin(note, !note.pinned) }
                        } label: {
                            Label(note.pinned ? "Bỏ ghim" : "Ghim", systemImage: "pin")
                        }
                        .tint(.orange)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await remove(note) }
                        } label: {
                            Label("Xoá", systemImage: "trash")
                        }
                        Button { editing = note } label: {
                            Label("Sửa", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
            }

            if notes.isEmpty && !loading {
                Text("Ngày này chưa có gì. Bấm + để viết.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(item: $editing) { note in
            EditNoteView(note: note) { await load() }
        }
        .overlay { if loading && notes.isEmpty { ProgressView() } }
        .refreshable { await load() }
        .task(id: reload) { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        error = await auth.perform {
            let response: NotesResponse = try await $0.get("/api/notes?date=\(date)")
            notes = response.notes
        }
    }

    private func pin(_ note: ApiNote, _ pinned: Bool) async {
        error = await auth.perform {
            let _: NoteResponse = try await $0.put("/api/notes/\(note.id)/pin", body: PinInput(pinned: pinned))
        }
        await load()
    }

    /// Xoa mem: worker chi danh dau `deleted_at`, hoan tac duoc tu Thung rac.
    private func remove(_ note: ApiNote) async {
        error = await auth.perform {
            try await $0.fire("/api/notes/\(note.id)", method: "DELETE")
        }
        await load()
    }
}

/// Note trong ngay. Anh tai qua ApiClient chu khong AsyncImage — /api/media doi
/// cookie, ma AsyncImage khong gan header duoc.
struct NoteCard: View {
    let note: ApiNote

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: noteTypeIcon(note.type))
                if note.pinned { Image(systemName: "pin.fill") }
                if let mood = note.mood { MoodFace(mood: mood, size: 18) }
                Text(formatTime(note.createdAt))
                if let location = note.location, !location.isEmpty {
                    Text("· \(location)").lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Note audio: byte trong /api/media la m4a, do vao RemoteImage thi
            // chi ra loi "khong tai duoc anh".
            if note.type == "audio" {
                if let url = note.mediaUrl { AudioPlayButton(path: url) }
            } else {
                ForEach(note.mediaUrls, id: \.self) { url in
                    RemoteImage(path: url)
                }
            }

            if !note.text.isEmpty {
                Text(note.text).font(.body)
            } else if note.type != "text" {
                Text(noteTypeLabel(note.type))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !note.tags.isEmpty {
                Text(note.tags.map { "#\($0)" }.joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Sua chu + mood cua mot note. Khong sua anh: PUT /api/notes/:id/media chi
/// thay duoc slot 0, de danh cho web.
private struct EditNoteView: View {
    let note: ApiNote
    let done: () async -> Void

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var mood: String
    @State private var error: String?
    @State private var saving = false

    init(note: ApiNote, done: @escaping () async -> Void) {
        self.note = note
        self.done = done
        _text = State(initialValue: note.text)
        _mood = State(initialValue: note.mood ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(note.type == "text" ? "Nội dung" : "Chú thích") {
                    TextField("Viết gì đó...", text: $text, axis: .vertical)
                        .lineLimit(3...12)
                }
                Section("Tâm trạng") {
                    MoodPicker(mood: $mood)
                }
                if let error {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle("Sửa ghi chú")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { Task { await save() } }
                        // Note text bat buoc co chu; note media cho caption rong.
                        .disabled(saving || (note.type == "text" && text.trimmed.isEmpty))
                }
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        error = await auth.perform { client in
            if text != note.text {
                let _: NoteResponse = try await client.put("/api/notes/\(note.id)", body: TextInput(text: text))
            }
            if mood != (note.mood ?? "") {
                let _: NoteResponse = try await client.put("/api/notes/\(note.id)/mood",
                                                           body: MoodInput(mood: mood.isEmpty ? nil : mood))
            }
        }
        if error == nil {
            await done()
            dismiss()
        }
    }
}

struct MoodPicker: View {
    /// "" = khong chon mood.
    @Binding var mood: String

    var body: some View {
        // 8 mood tren mot dong: iPhone nho nhat con ~320pt nen o phai <=38pt.
        HStack(spacing: 0) {
            ForEach(moods, id: \.emoji) { item in
                Button {
                    mood = mood == item.emoji ? "" : item.emoji
                } label: {
                    MoodFace(mood: item.emoji, size: 28)
                        .padding(5)
                        .frame(maxWidth: .infinity)
                        .background(mood == item.emoji ? Color.accentColor.opacity(0.2) : .clear)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label)
            }
        }
    }
}

/// Anh tu /api/media, tai bang ApiClient de gan duoc cookie. Cache trong bo
/// nho theo duong dan: cuon qua lui khong tai lai ca ngay anh.
struct RemoteImage: View {
    let path: String

    @EnvironmentObject private var auth: AuthStore
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if failed {
                Label("Không tải được ảnh", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().frame(height: 120)
            }
        }
        .task(id: path) {
            if let cached = await ImageCache.shared.image(for: path) {
                image = cached
                return
            }
            guard let client = auth.client,
                  let data = try? await client.media(path),
                  let loaded = UIImage(data: data) else {
                failed = true
                return
            }
            await ImageCache.shared.store(loaded, for: path)
            image = loaded
        }
    }
}

/// ponytail: cache khong gioi han so anh, doi sang NSCache neu bi canh bao bo nho.
actor ImageCache {
    static let shared = ImageCache()
    private var store: [String: UIImage] = [:]

    func image(for key: String) -> UIImage? { store[key] }
    func store(_ image: UIImage, for key: String) { store[key] = image }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Nghe lai ghi am. Phai tai qua ApiClient roi phat tu Data: AVPlayer khong
/// gan duoc header Cookie vao URL /api/media, ma worker chi nhan cookie.
struct AudioPlayButton: View {
    let path: String

    @EnvironmentObject private var auth: AuthStore
    @StateObject private var clip = AudioClip()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                Task { await clip.toggle(path: path, client: auth.client) }
            } label: {
                Label(clip.playing ? "Dừng" : "Nghe",
                      systemImage: clip.playing ? "stop.circle.fill" : "play.circle.fill")
            }
            .buttonStyle(.bordered)
            .disabled(clip.loading)
            .overlay(alignment: .trailing) {
                if clip.loading { ProgressView().padding(.trailing, -28) }
            }

            if let error = clip.error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
    }
}

@MainActor
final class AudioClip: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playing = false
    @Published private(set) var loading = false
    @Published private(set) var error: String?

    private var player: AVAudioPlayer?
    /// Giu lai byte da tai: bam Nghe lan hai khong goi mang nua.
    private var data: Data?

    func toggle(path: String, client: ApiClient?) async {
        if playing { stop(); return }
        guard let client else { return }

        if data == nil {
            loading = true
            data = try? await client.media(path)
            loading = false
        }
        guard let data else { error = "Không tải được ghi âm."; return }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.play()
            self.player = player
            playing = true
            error = nil
        } catch {
            self.error = "Không phát được: \(error.localizedDescription)"
        }
    }

    private func stop() {
        player?.stop()
        player = nil
        playing = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.player = nil
            self.playing = false
        }
    }
}
