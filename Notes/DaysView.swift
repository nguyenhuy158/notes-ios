import SwiftUI

/// Hai tab, khop dieu huong ben web (BottomNav: Lich / Cai dat — tab "Dong
/// thoi gian" ben web cung chi la danh sach theo ngay nen gop vao Lich).
struct RootTabs: View {
    var body: some View {
        TabView {
            DaysView()
                .tabItem { Label("Ngày", systemImage: "calendar") }
            // Tab rieng nen phai tu boc NavigationStack (khi o trong Cai dat
            // thi no dung stack cua Cai dat).
            NavigationStack { YearView() }
                .tabItem { Label("Năm", systemImage: "chart.bar") }
            SettingsView()
                .tabItem { Label("Cài đặt", systemImage: "gearshape") }
        }
    }
}

/// Danh sach ngay co note trong mot thang, moi moi nhat len tren. Lay tu
/// GET /api/days (mot query cho ca thang) chu khong goi /api/notes 30 lan.
struct DaysView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var month = monthString(Date())
    @State private var days: DaysResponse?
    @State private var error: String?
    @State private var loading = true
    @State private var composing: ComposeStart?

    /// Ngay co note, moi nhat truoc. Chuoi "YYYY-MM-DD" sort chuoi la dung thu tu.
    private var sortedDays: [String] {
        (days?.days.keys).map { $0.sorted(by: >) } ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }

                Section {
                    NavigationLink(value: dayString(Date())) {
                        Label("Hôm nay", systemImage: "sun.max")
                    }
                }

                Section {
                    ForEach(sortedDays, id: \.self) { day in
                        NavigationLink(value: day) {
                            DayRow(date: day,
                                   types: days?.days[day] ?? [],
                                   mood: days?.moods[day],
                                   tags: days?.tags[day] ?? [])
                        }
                    }
                    if sortedDays.isEmpty && !loading {
                        Text("Tháng này chưa có ghi chú nào.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    MonthHeader(month: $month)
                }
            }
            .navigationTitle("Nhật ký")
            .navigationDestination(for: String.self) { DayView(date: $0) }
            .toolbar {
                Button { composing = .blank } label: { Label("Ghi chú mới", systemImage: "plus") }
            }
            // Ghi nhanh: chon ghi am / chup anh / viet chu, luu vao hom nay.
            .overlay(alignment: .bottomTrailing) { RecordFab { composing = $0 } }
            .sheet(item: $composing) { start in
                ComposeView(date: dayString(Date()), start: start) { await load() }
            }
            .overlay { if loading && days == nil { ProgressView() } }
            .refreshable { await load() }
            .task(id: month) { await load() }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        error = await auth.perform {
            days = try await $0.get("/api/days?month=\(month)")
        }
    }
}

struct MonthHeader: View {
    @Binding var month: String

    var body: some View {
        HStack {
            Button { month = shiftMonth(month, by: -1) } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(formatMonthTitle(month))
            Spacer()
            Button { month = shiftMonth(month, by: 1) } label: {
                Image(systemName: "chevron.right")
            }
            // Thang sau hom nay chac chan rong, khong cho di tiep.
            .disabled(month >= monthString(Date()))
        }
        .buttonStyle(.borderless)
    }
}

private struct DayRow: View {
    let date: String
    let types: [String]
    let mood: String?
    let tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if let mood { MoodFace(mood: mood, size: 20) }
                Text(formatDayTitle(date)).fontWeight(.medium)
            }
            HStack(spacing: 8) {
                Text("\(types.count) ghi chú")
                // Dung Set: mot ngay 5 anh chi can mot icon anh.
                ForEach(Array(Set(types)).sorted(), id: \.self) { type in
                    Image(systemName: noteTypeIcon(type))
                }
                if !tags.isEmpty {
                    Text(tags.prefix(3).map { "#\($0)" }.joined(separator: " "))
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
