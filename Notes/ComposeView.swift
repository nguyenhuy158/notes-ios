import SwiftUI
import AVFoundation

/// Ly do app nay ton tai tren dien thoai: chup anh viet nhat ky ngay tai cho.
/// Chu + mood + dia diem + anh, mot lan POST /api/notes.
struct ComposeView: View {
    let date: String
    /// Mo san che do nao — cho nut noi ghi nhanh.
    var start: ComposeStart = .blank
    let done: () async -> Void

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var mood = ""
    @State private var location = ""
    @State private var tags = ""
    @State private var photos: [UIImage] = []
    @State private var picking = false
    @StateObject private var recorder = AudioRecorder()
    @State private var error: String?
    @State private var saving = false

    /// Note text bat buoc co chu; co anh roi thi chu la caption, de rong duoc.
    private var canSave: Bool {
        !saving && !recorder.recording && (recorder.clip != nil || !photos.isEmpty || !text.trimmed.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Hôm nay thế nào?", text: $text, axis: .vertical)
                        .lineLimit(4...14)
                }

                Section("Ghi âm") {
                    Button {
                        recorder.toggle()
                    } label: {
                        Label(recorder.recording ? "Dừng (\(recorder.duration)s)" : "Ghi âm",
                              systemImage: recorder.recording ? "stop.circle.fill" : "mic")
                            .foregroundStyle(recorder.recording ? .red : .accentColor)
                    }
                    if recorder.clip != nil && !recorder.recording {
                        HStack {
                            Label("Đã ghi \(recorder.duration)s", systemImage: "waveform")
                            Spacer()
                            Button("Xoá", role: .destructive) { recorder.discard() }
                        }
                        // Whisper chay ben worker, khong phai tren may.
                        Text("Để trống phần chữ thì server tự nhận diện giọng nói thành chữ.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let error = recorder.error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }

                // Worker chi nhan 1 file cho note audio -> khong tron anh vao.
                if recorder.clip == nil {
                Section("Ảnh") {
                    if !photos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(photos.enumerated()), id: \.offset) { index, image in
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 84, height: 84)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        .overlay(alignment: .topTrailing) {
                                            Button {
                                                photos.remove(at: index)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundStyle(.white, .black.opacity(0.6))
                                            }
                                            .buttonStyle(.plain)
                                            .padding(2)
                                        }
                                }
                            }
                        }
                    }
                    Button { picking = true } label: {
                        Label(photos.isEmpty ? "Chụp ảnh" : "Thêm ảnh", systemImage: "camera")
                    }
                    // Worker chan qua 10 anh mot note (1 chinh + 9 phu).
                    .disabled(photos.count >= maxPhotos)
                }
                }

                Section("Tâm trạng") {
                    MoodPicker(mood: $mood)
                }

                Section {
                    TextField("Địa điểm", text: $location)
                    TextField("Nhãn, cách nhau bằng dấu phẩy", text: $tags)
                        .autocorrectionDisabled()
                }

                if let error {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle(formatDayTitle(date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $picking) {
                ImagePicker { image in
                    picking = false
                    if let image { photos.append(image) }
                }
                .ignoresSafeArea()
            }
            .overlay { if saving { ProgressView() } }
            .task {
                switch start {
                case .blank: break
                case .record: if recorder.clip == nil && !recorder.recording { recorder.toggle() }
                case .camera: picking = true
                }
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let note = NewNote(date: date,
                           text: text,
                           mood: mood.isEmpty ? nil : mood,
                           location: location.trimmed,
                           tags: parseTagInput(tags),
                           photos: photos.compactMap { jpegData($0) },
                           audio: recorder.clip)
        error = await auth.perform { _ = try await $0.createNote(note) }
        if error == nil {
            await done()
            dismiss()
        }
    }
}

/// 1 anh chinh + 9 anh phu, dung MAX_EXTRA_PHOTOS ben worker.
let maxPhotos = 10

/// Worker chi nhan 5 nhan, moi nhan toi 24 ky tu — cat luon o day de khong gui
/// thu server se im lang bo di.
func parseTagInput(_ raw: String) -> [String] {
    var seen: [String] = []
    for part in raw.split(separator: ",") {
        let tag = String(String(part).trimmed.prefix(24))
        if !tag.isEmpty && !seen.contains(tag) { seen.append(tag) }
        if seen.count == 5 { break }
    }
    return seen
}

/// Anh 12MP cua iPhone la ~4MB JPEG goc. Ha canh dai ve 1600px roi nen lai:
/// nhat ky khong can do phan giai may anh, ma R2 thi tinh tien theo dung luong.
func jpegData(_ image: UIImage, maxEdge: CGFloat = 1600) -> Data? {
    let scale = min(1, maxEdge / max(image.size.width, image.size.height))
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)

    let renderer = UIGraphicsImageRenderer(size: size)
    let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    return resized.jpegData(compressionQuality: 0.7)
}

/// UIImagePickerController chu khong PhotosPicker: cai nay mo duoc camera, va
/// chup anh tai cho la ly do app nay o tren dien thoai.
struct ImagePicker: UIViewControllerRepresentable {
    let onPick: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        // May khong co camera (simulator) thi roi ve thu vien anh.
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (UIImage?) -> Void

        init(onPick: @escaping (UIImage?) -> Void) { self.onPick = onPick }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            onPick(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onPick(nil)
        }
    }
}

/// Ghi am ra m4a 16kHz mono: dung dinh dang worker cho phep ("audio/mp4"), va
/// 16k mono la dung cai Whisper can — file nho hon nhieu ma khong mat do chinh xac.
@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published private(set) var recording = false
    @Published private(set) var duration = 0
    @Published private(set) var clip: Data?
    @Published private(set) var error: String?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("notes-ios-clip.m4a")

    func toggle() { recording ? stop() : start() }

    func discard() {
        clip = nil
        duration = 0
    }

    private func start() {
        error = nil
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                guard granted else { self.error = "Chưa cho phép dùng micro."; return }
                self.beginRecording()
            }
        }
    }

    private func beginRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ])
            recorder.record()
            self.recorder = recorder
            clip = nil
            duration = 0
            recording = true
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.duration += 1 }
            }
        } catch {
            self.error = "Không ghi âm được: \(error.localizedDescription)"
        }
    }

    private func stop() {
        recorder?.stop()
        recorder = nil
        timer?.invalidate()
        timer = nil
        recording = false
        try? AVAudioSession.sharedInstance().setActive(false)
        clip = try? Data(contentsOf: url)
        if clip == nil { error = "Bản ghi bị rỗng." }
    }
}

/// Ghi nhanh: mo thang vao ghi am, camera, hay chi go chu.
enum ComposeStart: String, Identifiable, CaseIterable {
    case blank, record, camera

    var id: String { rawValue }

    var label: String {
        switch self {
        case .blank: return "Viết chữ"
        case .record: return "Ghi âm"
        case .camera: return "Chụp ảnh"
        }
    }

    var icon: String {
        switch self {
        case .blank: return "text.alignleft"
        case .record: return "mic"
        case .camera: return "camera"
        }
    }
}

/// Keo tu nut noi de chon loai note: len = ghi am, trai = viet chu,
/// phai = chup anh, xuong = thoi. Tha tay trong vung chet = viet chu.
enum FabIntent: Equatable {
    case open(ComposeStart)
    case cancel
}

func fabIntent(for translation: CGSize, threshold: CGFloat = 44) -> FabIntent {
    let dx = translation.width
    let dy = translation.height
    if max(abs(dx), abs(dy)) < threshold { return .open(.blank) }
    // Truc nao lech nhieu hon thi truc do quyet dinh.
    if abs(dy) >= abs(dx) { return dy < 0 ? .open(.record) : .cancel }
    return dx < 0 ? .open(.blank) : .open(.camera)
}

/// Nut noi ghi nhanh: bam la viet chu, giu roi keo de chon loai note.
struct RecordFab: View {
    let action: (ComposeStart) -> Void

    @GestureState private var drag: CGSize = .zero
    @State private var intent: FabIntent = .open(.blank)

    /// Vi tri cac lua chon quanh nut, cung huong voi cu chi keo.
    private let satellites: [(ComposeStart, CGSize)] = [
        (.record, CGSize(width: 0, height: -76)),
        (.blank, CGSize(width: -76, height: 0)),
        (.camera, CGSize(width: 76, height: 0)),
    ]

    private var dragging: Bool { drag != .zero }

    var body: some View {
        ZStack {
            ForEach(satellites, id: \.0) { start, offset in
                let active = dragging && intent == .open(start)
                Image(systemName: start.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(active ? .white : Color.accentColor)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(active ? Color.accentColor : Color(.secondarySystemBackground)))
                    .shadow(radius: 3, y: 2)
                    .offset(dragging ? offset : .zero)
                    .opacity(dragging ? 1 : 0)
                    .scaleEffect(active ? 1.25 : 1)
            }

            Image(systemName: intent == .cancel && dragging ? "xmark" : "plus")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Circle().fill(intent == .cancel && dragging ? Color.gray : Color.accentColor))
                .shadow(radius: 6, y: 3)
                // Nut di theo tay nhung khong qua xa, de biet la dang keo.
                .offset(x: max(-90, min(90, drag.width)), y: max(-90, min(90, drag.height)))
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: dragging)
        .animation(.easeOut(duration: 0.12), value: intent)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($drag) { value, state, _ in state = value.translation }
                .onChanged { value in
                    let next = fabIntent(for: value.translation)
                    if next != intent {
                        intent = next
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
                .onEnded { value in
                    let final = fabIntent(for: value.translation)
                    intent = .open(.blank)
                    if case .open(let start) = final { action(start) }
                }
        )
        .accessibilityLabel("Ghi nhanh")
        .accessibilityHint("Giữ rồi kéo lên để ghi âm, sang phải để chụp ảnh")
        .padding(.trailing, 20)
        .padding(.bottom, 24)
    }
}
