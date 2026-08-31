import SwiftUI

/// Nhan: dem so note theo nhan, doi ten nhan, xem note theo nhan.
struct TagsView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var tags: [TagCount] = []
    @State private var error: String?
    @State private var renaming: TagCount?

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            ForEach(tags) { tag in
                NavigationLink(value: TagRoute(tag: tag.tag)) {
                    HStack {
                        Text("#\(tag.tag)")
                        Spacer()
                        Text("\(tag.count)").foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button("Đổi tên") { renaming = tag }.tint(.orange)
                }
            }
            if tags.isEmpty && error == nil {
                Text("Chưa có nhãn nào.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Nhãn")
        .navigationDestination(for: TagRoute.self) { TagNotesView(tag: $0.tag) }
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $renaming) { tag in
            RenameTagSheet(tag: tag.tag) { await load() }
        }
    }

    private func load() async {
        error = await auth.perform { client in
            tags = try await (client.get("/api/tags") as TagsResponse).tags
        }
    }
}

/// NavigationLink(value:) can Hashable rieng — String da bi DaysView dung cho
/// route ngay, dung chung se nhay sang DayView.
struct TagRoute: Hashable {
    let tag: String
}

private struct RenameTagSheet: View {
    let tag: String
    let done: () async -> Void

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var error: String?

    init(tag: String, done: @escaping () async -> Void) {
        self.tag = tag
        self.done = done
        _name = State(initialValue: tag)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Tên nhãn", text: $name).autocorrectionDisabled()
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Đổi tên #\(tag)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { Task { await save() } }
                        .disabled(name.trimmed.isEmpty || name.trimmed == tag)
                }
            }
        }
    }

    private func save() async {
        error = await auth.perform { client in
            let _: RenameTagResponse = try await client.put(
                "/api/tags/rename", body: RenameTagInput(from: tag, to: name.trimmed))
        }
        if error == nil {
            await done()
            dismiss()
        }
    }
}

struct TagNotesView: View {
    let tag: String

    @EnvironmentObject private var auth: AuthStore
    @State private var notes: [ApiNote] = []
    @State private var error: String?

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatDayTitle(note.date)).font(.caption).foregroundStyle(.secondary)
                    NoteCard(note: note)
                }
            }
        }
        .navigationTitle("#\(tag)")
        .task {
            let query = tag.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? tag
            error = await auth.perform { client in
                notes = try await (client.get("/api/notes/by-tag?tag=\(query)") as NotesResponse).notes
            }
        }
    }
}

/// Album anh theo thang. Worker khong co endpoint "anh theo thang", nen tai
/// /api/export?format=json roi loc o may — JSON khong kem media nen nhe.
/// ponytail: nhieu nghin note thi doi sang endpoint rieng ben worker.
struct AlbumView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var notes: [ApiNote] = []
    @State private var month = monthString(Date())
    @State private var error: String?
    @State private var loading = true

    private var photos: [String] {
        notes.filter { $0.type == "photo" && $0.date.hasPrefix(month) }
            .flatMap(\.mediaUrls)
    }

    var body: some View {
        ScrollView {
            MonthHeader(month: $month)

            if let error { Text(error).foregroundStyle(.red).font(.footnote) }

            if loading {
                ProgressView().padding(.top, 40)
            } else if photos.isEmpty {
                Text("Tháng này chưa có ảnh.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 40)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 4)], spacing: 4) {
                    ForEach(photos, id: \.self) { url in
                        RemoteImage(path: url)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .navigationTitle("Album")
        .task {
            error = await auth.perform { client in
                notes = try await (client.get("/api/export?format=json") as ExportResponse).notes
            }
            loading = false
        }
    }
}

/// Tong ket nam: luoi 12 thang theo so note moi ngay + vai con so.
struct YearView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var data = YearResponse(counts: [:], moods: [:])
    @State private var error: String?

    private var summary: YearSummary { yearSummary(counts: data.counts, moods: data.moods) }

    var body: some View {
        ScrollView {
            HStack {
                Button { year -= 1 } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(String(year)).font(.headline)
                Spacer()
                Button { year += 1 } label: { Image(systemName: "chevron.right") }
                    .disabled(year >= Calendar.current.component(.year, from: Date()))
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if let error { Text(error).foregroundStyle(.red).font(.footnote) }

            HStack(spacing: 16) {
                stat("\(summary.total)", "note")
                stat("\(summary.days)", "ngày có ghi")
                stat("\(summary.longestStreak)", "chuỗi dài nhất")
                if let mood = summary.topMood {
                    VStack {
                        MoodFace(mood: mood, size: 24)
                        Text("hay gặp").font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 8)

            // 12 thang xep 3 cot cho vua mot man hinh, khong phai cuon 12 lan.
            LazyVGrid(columns: Array(repeating: GridItem(spacing: 12), count: 3), spacing: 12) {
                ForEach(1...12, id: \.self) { month in
                    MonthGrid(year: year, month: month, counts: data.counts)
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle("Tổng kết năm")
        .task(id: year) {
            error = await auth.perform { client in
                data = try await client.get("/api/year?year=\(year)")
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack {
            Text(value).font(.title3.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MonthGrid: View {
    let year: Int
    let month: Int
    let counts: [String: Int]

    /// So o trong truoc ngay 1 de cot thang nao cung dung thu trong tuan.
    private var offset: Int {
        let first = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1))!
        return (Calendar.current.component(.weekday, from: first) - Calendar.current.firstWeekday + 7) % 7
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Th\(month)").font(.caption2).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 11) }
                ForEach(1...daysIn(year: year, month: month), id: \.self) { day in
                    let count = counts[String(format: "%04d-%02d-%02d", year, month, day)]
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor.opacity(count == nil ? 0.08 : min(1, 0.35 + 0.25 * Double(count ?? 0))))
                        .frame(height: 11)
                }
            }
        }
    }
}

/// Khong tu tinh nam nhuan: Calendar biet roi.
func daysIn(year: Int, month: Int) -> Int {
    let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1))!
    return Calendar.current.range(of: .day, in: .month, for: date)?.count ?? 30
}

extension TagCount: Hashable {
    static func == (lhs: TagCount, rhs: TagCount) -> Bool { lhs.tag == rhs.tag }
    func hash(into hasher: inout Hasher) { hasher.combine(tag) }
}
