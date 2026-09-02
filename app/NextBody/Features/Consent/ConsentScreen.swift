import SwiftUI

/// 补屏 A · 同意屏 What HOOP collects. 390 wide; the content is ~1860 tall and scrolls;
/// the Continue sits in a fixed 104pt footer.
///
/// Rule 02 · one checkbox, one Continue. Not pre-checked, the list does not collapse, and it is
/// not folded into Terms or Privacy.
/// Rule 03 · two highlight phases, never both: unchecked is an amber-outlined box and a grey,
/// inert Continue with no lime anywhere on the screen; checked is a lime box and a lime Continue.
/// Rule 11 · 「填完之后会怎样」 is text only — no grey bars, no empty rings, no preview cards.
/// Declining · the chevron is the only other exit. Not ticking is not agreeing; there is no
/// second button.
struct ConsentScreen: View {
    let onContinue: () -> Void
    let onBack: () -> Void

    @State private var agreed = false
    @State private var shownAt = Date()
    @State private var scrolledToBox = false

    // The board's own values, not tokens: these are the colours the file draws this screen in.
    private let eyebrow = Color(hex: 0x6E6E76)
    private let ink = Color(hex: 0xF4F4F6)
    private let lede = Color(hex: 0xA6A6AE)
    private let bodyInk = Color(hex: 0x8A8A93)
    private let rule = Color(hex: 0x1A1A1E)

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    Button(action: decline) {
                        Text("‹")
                            .font(NBFont.brand(400, 24))
                            .foregroundStyle(NB.white.opacity(0.55))
                            .frame(width: 44, height: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                    .padding(.top, Chrome.statusBarBlock - 30)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(ConsentCopy.eyebrow).font(NBFont.dot(600, 11)).tracking(0.24 * 11).foregroundStyle(eyebrow)
                        Text(ConsentCopy.title).font(NBFont.brand(600, 34)).tracking(-0.01 * 34).lineSpacing(4).foregroundStyle(ink)
                        Text(ConsentCopy.lede).font(NBFont.ui(300, 15)).lineSpacing(8).foregroundStyle(lede)
                    }

                    ForEach(Array(ConsentCopy.sections.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 14) {
                            Text(section.head).font(NBFont.dot(600, 10)).tracking(0.24 * 10).foregroundStyle(eyebrow)
                            ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.name).font(NBFont.brand(500, 16)).lineSpacing(6).foregroundStyle(ink)
                                    Text(item.why).font(NBFont.ui(300, 13)).lineSpacing(6).foregroundStyle(bodyInk)
                                }
                            }
                        }
                        .padding(.top, 8)
                    }

                    ForEach(Array(ConsentCopy.notes.enumerated()), id: \.offset) { i, note in
                        VStack(alignment: .leading, spacing: 9) {
                            Text(note.head).font(NBFont.dot(600, 10)).tracking(0.24 * 10).foregroundStyle(eyebrow)
                            Text(note.body).font(NBFont.ui(300, 13)).lineSpacing(6).foregroundStyle(bodyInk)
                        }
                        .padding(.top, i == 0 ? 12 : 0)
                        .overlay(alignment: .top) { if i == 0 { rule.frame(height: 1) } }
                    }

                    // The checkbox row. The rule at the top, then the box and its sentence.
                    HStack(alignment: .top, spacing: 12) {
                        Button { withAnimation(.easeOut(duration: 0.12)) { agreed.toggle() } } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(agreed ? NB.lime1 : .clear)
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(agreed ? NB.lime1 : NB.ember1, lineWidth: 1)
                                if agreed {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(NB.carbon)
                                }
                            }
                            .frame(width: 20, height: 20)
                            .padding(12)                      // hit area ≥ 44
                            .contentShape(Rectangle())
                            .padding(-12)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(ConsentCopy.agree)
                        .accessibilityAddTraits(agreed ? [.isSelected] : [])
                        Text(ConsentCopy.agree).font(NBFont.ui(400, 15)).lineSpacing(7).foregroundStyle(ink)
                    }
                    .padding(.top, 14)
                    .overlay(alignment: .top) { rule.frame(height: 1) }
                    .onAppear {
                        guard !scrolledToBox else { return }
                        scrolledToBox = true
                        Task { await Analytics.shared.track("CONSENT_SCROLLED_TO_CHECKBOX", ["VERSION": ConsentStore.version]) }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text(ConsentCopy.ifNot).font(NBFont.ui(300, 13)).lineSpacing(6).foregroundStyle(bodyInk)
                        Text(ConsentCopy.withdraw).font(NBFont.ui(300, 13)).lineSpacing(6).foregroundStyle(bodyInk)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
                .frame(width: 390, alignment: .leading)
            }

            // 1F4L · 390 × 104, one 342 × 52 button. Grey and inert until the box is ticked.
            VStack(spacing: 0) {
                if agreed {
                    Button { Task { await accept() } } label: {
                        Text(ConsentCopy.cta)
                            .font(NBFont.ui(500, 13.5)).tracking(0.15 * 13.5)
                            .foregroundStyle(NB.carbon)
                            .frame(width: 342, height: 52)
                            .background(NB.lime1, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(ConsentCopy.cta)
                        .font(NBFont.ui(500, 13.5)).tracking(0.15 * 13.5)
                        .foregroundStyle(eyebrow)
                        .frame(width: 342, height: 52)
                        .background(rule, in: Capsule())
                        .accessibilityLabel("Continue · tick the box first")
                }
            }
            .frame(width: 390, height: 104)
            .background(NB.carbon)
        }
        // The list scrolls under the status bar like any list; the bar itself keeps its ground,
        // so a headline never collides with the clock.
        .overlay(alignment: .top) { Color.clear.frame(height: 0).background(NB.carbon.ignoresSafeArea(edges: .top)) }
        .background(NB.carbon.ignoresSafeArea())
        .task {
            shownAt = Date()
            await Analytics.shared.track("CONSENT_SHOWN", ["VERSION": ConsentStore.version,
                                                          "IS_DELTA": ConsentStore.shared.decided])
        }
    }

    private var msOnScreen: Int { Int(Date().timeIntervalSince(shownAt) * 1000) }

    private func accept() async {
        await ConsentStore.shared.record(.granted, msOnScreen: msOnScreen)
        onContinue()
    }

    private func decline() {
        Task {
            await ConsentStore.shared.record(.declined, msOnScreen: msOnScreen)
            onBack()
        }
    }
}
