import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var me: MeResponse?
    @State private var stats: StatsResponse?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }

                Section("Tài khoản") {
                    LabeledContent("Tên", value: me?.name ?? "…")
                    LabeledContent("Email", value: me?.email ?? "…")
                }

                Section("Đã ghi") {
                    LabeledContent("Số ghi chú", value: stats.map { "\($0.noteCount)" } ?? "…")
                    LabeledContent("Ảnh, âm thanh", value: stats.map { formatBytes($0.mediaBytes) } ?? "…")
                }

                Section {
                    NavigationLink("Nhãn") { TagsView() }
                    NavigationLink("Album ảnh") { AlbumView() }
                    NavigationLink("Thùng rác") { TrashView() }
                }

                Section {
                    Button("Đăng xuất", role: .destructive) { auth.signOut() }
                } footer: {
                    Text("Chia sẻ link, khoá PIN, xuất dữ liệu → vẫn làm trên notes.huyab.click.")
                }
            }
            .navigationTitle("Cài đặt")
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func load() async {
        error = await auth.perform { client in
            me = try await client.get("/api/me")
            stats = try await client.get("/api/stats")
        }
    }
}

/// Note da xoa mem. Khoi phuc hoac xoa vinh vien — media R2 chi mat o buoc purge.
struct TrashView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var notes: [ApiNote] = []
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        List {
            if let error {
                Text(error).foregroundStyle(.red).font(.footnote)
            }

            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: 3) {
                    Text(note.text.isEmpty ? noteTypeLabel(note.type) : note.text)
                        .lineLimit(2)
                    Text(formatDayTitle(note.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .swipeActions(edge: .leading) {
                    Button { Task { await act(note, "/restore", method: "POST") } } label: {
                        Label("Khôi phục", systemImage: "arrow.uturn.backward")
                    }
                    .tint(.green)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await act(note, "/purge", method: "DELETE") }
                    } label: {
                        Label("Xoá hẳn", systemImage: "trash")
                    }
                }
            }

            if notes.isEmpty && !loading {
                Text("Thùng rác trống.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Thùng rác")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if loading && notes.isEmpty { ProgressView() } }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        error = await auth.perform {
            let response: NotesResponse = try await $0.get("/api/trash")
            notes = response.notes
        }
    }

    private func act(_ note: ApiNote, _ suffix: String, method: String) async {
        error = await auth.perform {
            try await $0.fire("/api/notes/\(note.id)\(suffix)", method: method)
        }
        await load()
    }
}
