import SwiftUI
import UIKit

// 03 · three sheets, one rule: change a value without leaving the table.
//  01 the sheet never passes 62% of the screen; the screen underneath keeps its title and a value row
//  02 it opens on the current value — not empty, not the median
//  03 once really edited, HEALTH becomes EDIT for good
//  04 Save is the only commit. Swiping down = discard, same as Cancel, and nothing asks "are you sure"
//  05 the unit is a property of the account, switched here once and honoured everywhere
//  06 all three must work one-handed: draggable in the right half, Save under the thumb
//  07 sex has no sheet — two options do not deserve a panel

private struct SheetShell<Content: View>: View {
    let title: String
    var trailing: AnyView?
    let saveTitle: String
    var showCancel = false
    let onSave: () -> Void
    var onCancel: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text(title)
                    .font(NBFont.ui(500, 20)).tracking(0.01 * 20)
                    .foregroundStyle(NB.text1)
                Spacer(minLength: 0)
                if let trailing { trailing }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)

            content

            Spacer(minLength: 0)

            LimePillButton(title: L(saveTitle), action: onSave)
                .padding(.bottom, showCancel ? 8 : 22)

            if showCancel, let onCancel {
                Button(action: onCancel) {
                    Text(L("Cancel"))
                        .font(NBFont.ui(400, 13)).tracking(0.02 * 13)
                        .foregroundStyle(NB.white.opacity(0.42))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 22)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NB.carbon2)
    }
}

struct UnitToggle: View {
    let options: [String]
    @Binding var selection: String
    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { o in
                Button { selection = o } label: {
                    Text(o)
                        .font(NBFont.ui(500, 11)).tracking(0.12 * 11)
                        .foregroundStyle(selection == o ? NB.carbon : NB.white.opacity(0.5))
                        .padding(.horizontal, 12).frame(height: 26)
                        .background(selection == o ? NB.lime1 : Color.clear, in: Capsule())
                        .overlay(selection == o ? nil : Capsule().stroke(NB.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: 1 · WEIGHT · RULER

/// The ruler starts on the number that came back from the sync, never on a round number in
/// the middle. One notch is 0.1 kg with a light haptic per whole unit — the feel is telling
/// the user "you are standing on 63".
struct WeightRulerSheet: View {
    @Binding var value: Double
    let onSave: () -> Void

    @State private var unit = "KG"
    @State private var draft: Double = 0
    @State private var lastWhole: Int = 0
    @State private var typing = false
    @State private var typed = ""

    private var display: Double { unit == "KG" ? draft : draft * 2.2046226 }

    var body: some View {
        SheetShell(title: L("Weight"),
                   trailing: AnyView(UnitToggle(options: ["KG", "LB"], selection: $unit)),
                   saveTitle: "Save", onSave: { value = draft; onSave() }) {
            VStack(spacing: 0) {
                // "tap the number to type" is mandatory: dragging from 63 to 95 is thirty
                // seconds of shaking, and that person is the key user.
                Button { typing = true } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", display))
                            .font(NBFont.brand(700, 64)).tracking(-0.045 * 64)
                            .foregroundStyle(NB.text1)
                        Text(unit.lowercased())
                            .font(NBFont.ui(300, 18))
                            .foregroundStyle(NB.white.opacity(0.42))
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 34)

                HorizontalRuler(value: $draft, range: 30...200, step: 0.1, majorEvery: 10)
                    .frame(height: 74)
                    .padding(.top, 26)

                Text(L("Drag the ruler, or tap the number to type"))
                    .font(NBFont.ui(300, 12.5)).tracking(0.02 * 12.5)
                    .foregroundStyle(NB.white.opacity(0.38))
                    .padding(.top, 18)
            }
        }
        .onAppear { draft = value; lastWhole = Int(value) }
        .onChange(of: draft) { _, v in
            if Int(v) != lastWhole {
                lastWhole = Int(v)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
        .alert("Weight", isPresented: $typing) {
            TextField("kg", text: $typed).keyboardType(.decimalPad)
            Button("Set") { if let d = Double(typed) { draft = unit == "KG" ? d : d / 2.2046226 } }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct HorizontalRuler: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let majorEvery: Int

    private let pitch: CGFloat = 9

    var body: some View {
        GeometryReader { geo in
            let mid = geo.size.width / 2
            ZStack {
                Canvas { ctx, size in
                    let first = Int(((value - Double(mid / pitch) * step) / step).rounded())
                    let count = Int(size.width / pitch) + 2
                    for i in 0..<count {
                        let idx = first + i
                        let v = Double(idx) * step
                        guard range.contains(v) else { continue }
                        let x = mid + CGFloat(v - value) / CGFloat(step) * pitch
                        let major = idx % majorEvery == 0
                        let h: CGFloat = major ? 26 : 14
                        ctx.fill(Path(CGRect(x: x, y: 24 - h / 2, width: 1.4, height: h)),
                                 with: .color(NB.white.opacity(major ? 0.55 : 0.22)))
                        if major {
                            ctx.draw(Text(String(format: "%.0f", v))
                                .font(NBFont.dot(500, 10)).foregroundColor(NB.white.opacity(0.34)),
                                     at: CGPoint(x: x, y: 52))
                        }
                    }
                }
                Rectangle().fill(NB.lime1).frame(width: 2, height: 34).position(x: mid, y: 24)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture()
                .onChanged { g in
                    let delta = -Double(g.translation.width / pitch) * step
                    value = min(max(range.lowerBound, value + delta / 12), range.upperBound)
                })
        }
    }
}

// MARK: 2 · HEIGHT · VERTICAL

/// The same ruler, turned upright — the axis follows the quantity. Standing a horizontal
/// ruler on end makes people hesitate before touching it; numbers on the left, ticks on the
/// right, because a thumb only reaches the right edge.
struct HeightRulerSheet: View {
    @Binding var value: Double
    let onSave: () -> Void

    @State private var unit = "CM"
    @State private var draft: Double = 0
    @State private var typing = false
    @State private var typed = ""

    var body: some View {
        SheetShell(title: L("Height"),
                   trailing: AnyView(UnitToggle(options: ["CM", "FT"], selection: $unit)),
                   saveTitle: "Save", onSave: { value = draft; onSave() }) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    Button { typing = true } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(unit == "CM" ? "\(Int(draft))" : feetInches(draft))
                                .font(NBFont.brand(700, 64)).tracking(-0.045 * 64)
                                .foregroundStyle(NB.text1)
                            Text(unit.lowercased())
                                .font(NBFont.ui(300, 18))
                                .foregroundStyle(NB.white.opacity(0.42))
                        }
                    }
                    .buttonStyle(.plain)

                    Text(L("Drag the scale, or tap the number to type"))
                        .font(NBFont.ui(300, 12.5)).tracking(0.02 * 12.5)
                        .foregroundStyle(NB.white.opacity(0.38))
                        .frame(width: 190, alignment: .leading)
                }
                .padding(.leading, 24)
                .padding(.top, 30)

                Spacer(minLength: 0)

                VerticalRuler(value: $draft, range: 120...220)
                    .frame(width: 96, height: 250)
                    .padding(.trailing, 20)
                    .padding(.top, 8)
            }
        }
        .onAppear { draft = value }
        .alert("Height", isPresented: $typing) {
            TextField("cm", text: $typed).keyboardType(.numberPad)
            Button("Set") { if let d = Double(typed) { draft = d } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func feetInches(_ cm: Double) -> String {
        let inches = cm / 2.54
        return "\(Int(inches) / 12)'\(Int(inches) % 12)\""
    }
}

struct VerticalRuler: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    private let pitch: CGFloat = 11

    var body: some View {
        GeometryReader { geo in
            let mid = geo.size.height / 2
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    let count = Int(size.height / pitch) + 2
                    let first = Int(value - Double(mid / pitch))
                    for i in 0..<count {
                        let v = Double(first + i)
                        guard range.contains(v) else { continue }
                        let y = mid - CGFloat(v - value) * pitch
                        let major = Int(v) % 5 == 0
                        ctx.fill(Path(CGRect(x: size.width - (major ? 30 : 18), y: y,
                                             width: major ? 30 : 18, height: 1.4)),
                                 with: .color(NB.white.opacity(major ? 0.5 : 0.2)))
                        if Int(v) % 10 == 0 {
                            ctx.draw(Text("\(Int(v))")
                                .font(NBFont.dot(500, 10)).foregroundColor(NB.white.opacity(0.34)),
                                     at: CGPoint(x: size.width - 46, y: y))
                        }
                    }
                }
                Rectangle().fill(NB.lime1)
                    .frame(width: 46, height: 2)
                    .position(x: geo.size.width - 23, y: mid)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture()
                .onChanged { g in
                    value = min(max(range.lowerBound, value + Double(g.translation.height / pitch) / 10),
                                range.upperBound)
                })
        }
    }
}

// MARK: 3 · BIRTHDAY · HAS CANCEL

/// AGE 28 in the top-right tracks the wheel live. A birthday is the one field of the four a
/// user cannot "feel is wrong", so the derived age sits next to it. It is also the only sheet
/// with a Cancel — a wheel has no "untouched" state, so one slip has already committed.
struct BirthdayWheelSheet: View {
    @Binding var value: DateComponents
    let onSave: (DateComponents) -> Void
    let onCancel: () -> Void

    @State private var date = Date()

    private var age: Int {
        Calendar.current.dateComponents([.year], from: date, to: Date()).year ?? 0
    }

    var body: some View {
        SheetShell(title: L("Birthday"),
                   trailing: AnyView(
                        Text(L("AGE %d", age))
                            .font(NBFont.dot(600, 10)).tracking(0.24 * 10)
                            .foregroundStyle(NB.lime1)
                            .contentTransition(.numericText())),
                   saveTitle: "Save",
                   showCancel: true,
                   onSave: {
                        onSave(Calendar.current.dateComponents([.year, .month, .day], from: date))
                   },
                   onCancel: onCancel) {
            VStack(spacing: 18) {
                DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .colorScheme(.dark)
                    .frame(height: 190)
                    .padding(.top, 10)

                Text(L("Age drives the body-composition model — worth getting right."))
                    .font(NBFont.ui(300, 12.5)).tracking(0.02 * 12.5)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(NB.white.opacity(0.38))
                    .frame(width: 300)
            }
        }
        .onAppear { date = Calendar.current.date(from: value) ?? Date() }
    }
}
