import SwiftUI

/// The two faces, and how to put one on the home screen.
///
/// ⚠️ This sheet exists because of a funnel nobody could see. A background pull is only
/// scheduled when a widget is installed — without one there is no reader, so the app does
/// not light up the radio (ADR 0026) — and until now nothing in the product ever said the
/// word "widget" to anyone. A person who never long-pressed their home screen simply had a
/// quieter app and no way to know why.
///
/// The previews are drawn, not screenshotted: a picture of numbers from somebody else's day
/// would be the one thing on this page making a claim.
struct WidgetsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetFrame(title: L("Widgets"), fillsHeight: false) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    todayFace
                    shotFace
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    step(1, L("Touch and hold an empty spot on your home screen."))
                    step(2, L("Tap the + in the corner, then search for NEXTBODY."))
                    step(3, L("Pick TODAY or LOG A MEAL and add it."))
                }

                Text(L("A widget is also the only reader the app syncs for in the background. With one on your home screen the day's numbers stay current between opens; without one, nothing is fetched until you open the app."))
                    .font(NBFont.ui(300, 12.5)).tracking(0.02 * 12.5)
                    .foregroundStyle(NB.white.opacity(0.38))
                    .fixedSize(horizontal: false, vertical: true)
            }
        } footer: {
            LimePillButton(title: L("Done"), enabled: true) { dismiss() }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(NBFont.dot(700, 11))
                .foregroundStyle(NB.lime1)
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(NB.lime1.opacity(0.4), lineWidth: 1))
            Text(text)
                .font(NBFont.ui(400, 13.5))
                .foregroundStyle(NB.text1)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var todayFace: some View {
        face(title: L("TODAY")) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("BODY BATTERY"))
                    .font(NBFont.dot(600, 7)).tracking(0.18 * 7)
                    .foregroundStyle(NB.white.opacity(0.4))
                Text("72")
                    .font(NBFont.dot(700, 30))
                    .foregroundStyle(NB.lime1)
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    miniFact(L("LOAD"), "12.4", NB.lime1)
                    miniFact(L("EATEN"), "1,240", NB.ember1)
                }
            }
        }
    }

    private var shotFace: some View {
        face(title: L("LOG A MEAL")) {
            VStack(alignment: .leading, spacing: 8) {
                Spacer(minLength: 0)
                Image(systemName: "camera")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(NB.ember1)
                Text(L("PHOTOGRAPH\nTHE PLATE"))
                    .font(NBFont.dot(600, 9)).tracking(0.14 * 9)
                    .foregroundStyle(NB.white.opacity(0.62))
                Spacer(minLength: 0)
            }
        }
    }

    private func face<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
                .padding(12)
                .frame(width: 132, height: 132, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(NB.carbon))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(NB.hairline, lineWidth: 1))
            Text(title)
                .font(NBFont.dot(600, 10)).tracking(0.14 * 10)
                .foregroundStyle(NB.text3Prod)
        }
    }

    private func miniFact(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(NBFont.dot(600, 7)).tracking(0.18 * 7)
                .foregroundStyle(NB.white.opacity(0.4))
            Text(value)
                .font(NBFont.dot(700, 12))
                .foregroundStyle(tint)
        }
    }
}
