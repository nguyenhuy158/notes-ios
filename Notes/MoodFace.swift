import SwiftUI

/// Mat tu ve thay cho emoji he thong. Gia tri luu VAN la ky tu unicode trong
/// whitelist MOODS cua worker ("😄"...) — chi doi phan hien thi, khong dung
/// schema. Doi sang emoji tu chon that thi phai sua whitelist ben worker.
enum EyeStyle { case dot, arc, slant, closed, wide }
enum MouthStyle { case bigSmile, smile, flat, frown, oh }

struct MoodFaceSpec {
    let bg: Color
    let eyes: EyeStyle
    let mouth: MouthStyle
    var sweat = false
    var confetti = false
}

func moodFaceSpec(_ mood: String) -> MoodFaceSpec? {
    switch mood {
    case "😄": return MoodFaceSpec(bg: Color(red: 1.00, green: 0.85, blue: 0.35), eyes: .arc, mouth: .bigSmile)
    case "🙂": return MoodFaceSpec(bg: Color(red: 1.00, green: 0.80, blue: 0.62), eyes: .dot, mouth: .smile)
    case "😐": return MoodFaceSpec(bg: Color(red: 0.80, green: 0.84, blue: 0.88), eyes: .dot, mouth: .flat)
    case "😔": return MoodFaceSpec(bg: Color(red: 0.62, green: 0.76, blue: 0.95), eyes: .arc, mouth: .frown)
    case "😡": return MoodFaceSpec(bg: Color(red: 0.98, green: 0.52, blue: 0.48), eyes: .slant, mouth: .frown)
    case "😴": return MoodFaceSpec(bg: Color(red: 0.78, green: 0.72, blue: 0.95), eyes: .closed, mouth: .oh)
    case "🥳": return MoodFaceSpec(bg: Color(red: 0.60, green: 0.88, blue: 0.66), eyes: .dot, mouth: .bigSmile, confetti: true)
    case "😰": return MoodFaceSpec(bg: Color(red: 0.58, green: 0.87, blue: 0.90), eyes: .wide, mouth: .frown, sweat: true)
    default: return nil
    }
}

/// Ve trong he toa do 48x48 roi scale — de doi `size` o moi cho dung.
struct MoodFace: View {
    let mood: String
    var size: CGFloat = 26

    var body: some View {
        Canvas { ctx, _ in
            guard let spec = moodFaceSpec(mood) else { return }
            let s = size / 48
            let ink = Color(white: 0.1)
            let line = 2 * s

            let face = Path(ellipseIn: CGRect(x: 3 * s, y: 3 * s, width: 42 * s, height: 42 * s))
            ctx.fill(face, with: .color(spec.bg))
            ctx.stroke(face, with: .color(ink), lineWidth: line)

            // Ma hong: bo khi mat dang nham/giận cho khoi rối.
            if spec.eyes != .slant {
                for x in [13.0, 35.0] {
                    ctx.fill(Path(ellipseIn: CGRect(x: (x - 4) * s, y: 27 * s, width: 8 * s, height: 5 * s)),
                             with: .color(Color(red: 1, green: 0.62, blue: 0.70).opacity(0.7)))
                }
            }

            for x in [16.0, 32.0] {
                var eye = Path()
                switch spec.eyes {
                case .dot:
                    eye = Path(ellipseIn: CGRect(x: (x - 2.6) * s, y: 18 * s, width: 5.2 * s, height: 6 * s))
                    ctx.fill(eye, with: .color(ink))
                    continue
                case .wide:
                    eye = Path(ellipseIn: CGRect(x: (x - 4) * s, y: 16 * s, width: 8 * s, height: 9 * s))
                    ctx.fill(eye, with: .color(.white))
                    ctx.stroke(eye, with: .color(ink), lineWidth: line)
                    ctx.fill(Path(ellipseIn: CGRect(x: (x - 1.6) * s, y: 19 * s, width: 3.2 * s, height: 3.6 * s)),
                             with: .color(ink))
                    continue
                case .arc:
                    eye.move(to: CGPoint(x: (x - 4) * s, y: 22 * s))
                    eye.addQuadCurve(to: CGPoint(x: (x + 4) * s, y: 22 * s),
                                     control: CGPoint(x: x * s, y: 15 * s))
                case .closed:
                    eye.move(to: CGPoint(x: (x - 4) * s, y: 21 * s))
                    eye.addQuadCurve(to: CGPoint(x: (x + 4) * s, y: 21 * s),
                                     control: CGPoint(x: x * s, y: 25 * s))
                case .slant:
                    let inner = x < 24 ? (x + 4) : (x - 4)
                    let outer = x < 24 ? (x - 4) : (x + 4)
                    eye.move(to: CGPoint(x: outer * s, y: 18 * s))
                    eye.addLine(to: CGPoint(x: inner * s, y: 23 * s))
                }
                ctx.stroke(eye, with: .color(ink), lineWidth: line)
            }

            var mouth = Path()
            switch spec.mouth {
            case .bigSmile:
                mouth.move(to: CGPoint(x: 16 * s, y: 30 * s))
                mouth.addQuadCurve(to: CGPoint(x: 32 * s, y: 30 * s),
                                   control: CGPoint(x: 24 * s, y: 40 * s))
            case .smile:
                mouth.move(to: CGPoint(x: 19 * s, y: 31 * s))
                mouth.addQuadCurve(to: CGPoint(x: 29 * s, y: 31 * s),
                                   control: CGPoint(x: 24 * s, y: 36 * s))
            case .flat:
                mouth.move(to: CGPoint(x: 19 * s, y: 33 * s))
                mouth.addLine(to: CGPoint(x: 29 * s, y: 33 * s))
            case .frown:
                mouth.move(to: CGPoint(x: 19 * s, y: 36 * s))
                mouth.addQuadCurve(to: CGPoint(x: 29 * s, y: 36 * s),
                                   control: CGPoint(x: 24 * s, y: 30 * s))
            case .oh:
                mouth = Path(ellipseIn: CGRect(x: 21 * s, y: 30 * s, width: 6 * s, height: 7 * s))
            }
            ctx.stroke(mouth, with: .color(ink), lineWidth: line)

            if spec.sweat {
                ctx.fill(Path(ellipseIn: CGRect(x: 37 * s, y: 10 * s, width: 5 * s, height: 7 * s)),
                         with: .color(Color(red: 0.35, green: 0.65, blue: 0.95)))
            }
            if spec.confetti {
                for (x, y, c) in [(8.0, 8.0, Color.pink), (40.0, 9.0, Color.yellow), (42.0, 34.0, Color.purple)] {
                    ctx.fill(Path(ellipseIn: CGRect(x: x * s, y: y * s, width: 4 * s, height: 4 * s)),
                             with: .color(c))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(moods.first { $0.emoji == mood }?.label ?? mood)
    }
}
