import SwiftUI
import UIKit

/// Design geometry: 390 × 844 with a 358 content column.
/// The board draws its own status bar at 62px tall; on device iOS draws it for us,
/// so we reserve the same 62px and let the system paint into it.
enum Chrome {
    /// The boards draw their own 62pt status-bar block; on device iOS paints into the same
    /// 47pt and we make up the difference.
    static let statusBarBlock: CGFloat = 62
    static let homeIndicatorBlock: CGFloat = 19

    /// The gate screens put their header line at y = 66. Inside the safe area that is 19pt.
    static let gateTopInset: CGFloat = 19
}

struct HomeIndicator: View {
    var body: some View {
        Capsule()
            .fill(NB.white.opacity(0.35))
            .frame(width: 134, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 6)
    }
}

/// The one page background. #0B0B0D, edge to edge.
struct CarbonBackground: ViewModifier {
    func body(content: Content) -> some View {
        ZStack { NB.carbon.ignoresSafeArea(); content }
    }
}

extension View {
    func carbonPage() -> some View { modifier(CarbonBackground()) }
}

/// NEXTBODY · lime pip. Inter Tight 800 @24, tracking −0.01em.
struct Wordmark: View {
    var size: CGFloat = 24
    var body: some View {
        HStack(spacing: 7) {
            Text("NEXTBODY")
                .font(NBFont.brand(800, size))
                .tracking(-0.01 * size)
                .foregroundStyle(NB.text1)
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(NB.lime1)
                .frame(width: 6, height: 6)
        }
    }
}

/// The band's own battery, as the header draws it — a 12×7 dot-matrix cell scaled to
/// 22×13, plus a Doto percentage.
struct BandBatteryPip: View {
    let percent: Int
    var body: some View {
        HStack(spacing: 6) {
            Canvas { ctx, size in
                let s = size.width / 12                       // viewBox is 12 × 7
                func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: Color) {
                    ctx.fill(Path(CGRect(x: x * s, y: y * s, width: w * s, height: h * s)), with: .color(c))
                }
                let shell = Color(hex: 0x3A3A44)
                rect(0, 0, 10, 1, shell)
                rect(0, 6, 10, 1, shell)
                rect(0, 1, 1, 5, shell)
                rect(9, 1, 1, 5, shell)
                rect(10, 2, 2, 3, shell)
                rect(1, 1, 8 * CGFloat(percent) / 100, 5, NB.lime2)
            }
            .frame(width: 22, height: 13)

            Text("\(percent)%")
                .font(NBFont.dot(700, 11))
                .tracking(0.06 * 11)
                .foregroundStyle(NB.limePale)
        }
    }
}

/// The only way into 11 · Profile.
struct AvatarButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image("Avatar")
                .resizable()
                .scaledToFill()
                .frame(width: 26, height: 26)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(hex: 0xF3F3F3, opacity: 0.8), lineWidth: 1))
                // F1 · 上线前必须成立 · 「热区不小于 44×44」. The avatar is the only way into
                // Profile and it was tappable at exactly its own 26pt, measuring 27 × 39 on
                // device. The padding is added and taken back out so the hit area reaches 44
                // while the header row stays the 26pt tall the board draws.
                .padding(9)
                .contentShape(Rectangle())
                .padding(-9)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("我的")
    }
}

/// 04 · header row. 358 wide, 2px inset, wordmark left, band battery + avatar right.
struct HomeHeader: View {
    let batteryPercent: Int
    let onAvatar: () -> Void
    #if DEBUG
    @State private var catalogue = false
    #endif
    var body: some View {
        HStack(spacing: 0) {
            Wordmark()
            #if DEBUG
                // 07's catalogue is the one board that cannot be audited by using the app,
                // because which widget appears is the model's choice. A long press opens
                // every type at once. DEBUG only — it is not a product surface.
                .onLongPressGesture(minimumDuration: 0.8) { catalogue = true }
                .fullScreenCover(isPresented: $catalogue) { WidgetCatalogue() }
            #endif
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                BandBatteryPip(percent: batteryPercent)
                AvatarButton(action: onAvatar)
            }
        }
        .padding(2)
        .frame(width: NB.Layout.contentWidth, height: 30)
    }
}

/// Detail pages share one header: a close mark on the left, an eyebrow, and nothing else.
struct DetailHeader: View {
    let eyebrow: String
    let title: String
    var trailing: String? = nil
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                Button(action: onClose) {
                    CloseMark()
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                if let trailing {
                    Text(trailing)
                        .font(NBFont.dot(500, 10))
                        .tracking(0.2 * 10)
                        .foregroundStyle(NB.text3)
                }
            }
            Text(eyebrow)
                .font(NBFont.ui(500, 11))
                .tracking(0.34 * 11)
                .foregroundStyle(NB.text3Prod)
            Text(title)
                .font(NBFont.brand(700, 32))
                .tracking(0.01 * 32)
                .foregroundStyle(NB.text1)
        }
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
    }
}

/// The close mark. The only exit from a takeover, and the back affordance on every detail page.
struct CloseMark: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(NB.carbon4)
                .overlay(Circle().stroke(NB.hairline, lineWidth: 1))
            Path { p in
                p.move(to: CGPoint(x: 8, y: 8)); p.addLine(to: CGPoint(x: 18, y: 18))
                p.move(to: CGPoint(x: 18, y: 8)); p.addLine(to: CGPoint(x: 8, y: 18))
            }
            .stroke(NB.iconInk, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .frame(width: 26, height: 26)
        }
        .frame(width: 36, height: 36)
    }
}

/// A hairline rule. 1px, white 8%.
struct Hairline: View {
    var width: CGFloat? = nil
    var body: some View {
        Rectangle().fill(NB.hairline).frame(width: width, height: 1)
    }
}

/// 05 · the dock is the only thing that moves when the keyboard comes up.
/// Everything else on the home screen stays exactly where it was.
@MainActor
final class KeyboardHeight: ObservableObject {
    @Published var height: CGFloat = 0

    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil, queue: .main) { [weak self] note in
                guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                        as? CGRect else { return }
                let screen = UIScreen.main.bounds.height
                MainActor.assumeIsolated { self?.height = max(0, screen - frame.origin.y) }
            })
        observers.append(center.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.height = 0 }
            })
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}
