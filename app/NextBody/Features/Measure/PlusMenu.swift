import SwiftUI

/// 06 · 加号与那张单子. One key, two groups, and there is never a third.
/// The camera moved out of the dock's right slot and became the plus; the menu that opens
/// is not an icon grid, because grouping here answers "who does the work":
/// ADD is something you hand her, MEASURE is something the band goes and does.
struct PlusMenuSheet: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var data: DataStore
    @Environment(\.dismiss) private var dismiss

    // F6 §05 · a measurement this HOOP cannot do is not offered at all, rather than offered
    // greyed out with the reason written in the row. A row you cannot press is still a row
    // about a thing you now want.
    private var canHeartRate: Bool { !data.capabilities.knownUnsupported(.heartRate) }
    private var canBodyScan: Bool { !data.capabilities.knownUnsupported(.bodyComposition) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupHeader("ADD TO THE MESSAGE")
            MenuRow(icon: .camera, title: "Take a photo",
                    detail: "Camera, straight into the message.") { dismiss() }
            MenuRow(icon: .library, title: "Photo library",
                    detail: "Pick one you already have.") { dismiss() }
            MenuRow(icon: .files, title: "Files",
                    detail: "A lab PDF or an export.") { dismiss() }

            // The header goes with the rows. A group heading standing over nothing reads as a
            // section that failed to load, which is the opposite of what an absent row means.
            if canHeartRate || canBodyScan {
                Hairline().padding(.vertical, 8)

                GroupHeader("MEASURE ON THE BAND")
                // Pressing a row is the confirmation. "60 S" is already printed on it, so a
                // second "are you sure, 60 seconds?" box would be asking a question already answered.
                // 06 edge 6 · NO BAND: the two band rows are dimmed in the sheet with the reason;
                // the measuring screen is never entered.
                let offline: String? = data.band.connected ? nil : "The band isn't connected."
                if canHeartRate {
                    MenuRow(icon: .pulse, title: "Battery check",
                            detail: "Heart rate, HRV and stress, in one.",
                            duration: "60 S", unavailable: offline) {
                        dismiss()
                        router.takeover = .measure(.heartRate)
                    }
                }
                if canBodyScan {
                    MenuRow(icon: .body, title: "Body scan",
                            detail: "Fourteen fields — fat, muscle, water.",
                            duration: "30 S", unavailable: offline) {
                        dismiss()
                        router.takeover = .measure(.bodyComposition)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NB.carbon2)
    }
}

private struct GroupHeader: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text)
            .font(NBFont.dot(600, 10)).tracking(0.2 * 10)
            .foregroundStyle(NB.white.opacity(0.30))
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
    }
}

private struct MenuRow: View {
    enum Icon { case camera, library, files, pulse, body }
    let icon: Icon
    let title: String
    let detail: String
    var duration: String? = nil
    /// A capability the band does not have keeps its row and states the reason in amber —
    /// hiding it would make the user think the feature does not exist.
    var unavailable: String? = nil
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                MenuIcon(kind: icon, tint: unavailable == nil ? NB.iconInk : NB.white.opacity(0.32))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(NBFont.ui(500, 15)).tracking(0.01 * 15)
                        .foregroundStyle(unavailable == nil ? NB.text1 : NB.white.opacity(0.42))
                    Text(unavailable ?? detail)
                        .font(unavailable == nil ? NBFont.ui(400, 12) : NBFont.dot(600, 10))
                        .tracking(unavailable == nil ? 0.02 * 12 : 0.16 * 10)
                        .foregroundStyle(unavailable == nil ? NB.white.opacity(0.42) : NB.ember1)
                }
                Spacer(minLength: 0)
                if let duration {
                    Text(duration)
                        .font(NBFont.dot(500, 10)).tracking(0.16 * 10)
                        .foregroundStyle(NB.white.opacity(0.30))
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 62)
            .background(pressed ? NB.lime1 : .clear,
                        in: RoundedRectangle(cornerRadius: NB.R.tile, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(unavailable != nil)
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in withAnimation(.easeOut(duration: 0.12)) { pressed = true } }
            .onEnded { _ in withAnimation(.easeOut(duration: 0.12)) { pressed = false } })
    }
}

private struct MenuIcon: View {
    let kind: MenuRow.Icon
    let tint: Color

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 24
            let ink = GraphicsContext.Shading.color(tint)
            let stroke = StrokeStyle(lineWidth: 1.6 * s, lineCap: .round, lineJoin: .round)
            switch kind {
            case .camera:
                ctx.stroke(Path(roundedRect: CGRect(x: 3 * s, y: 7 * s, width: 18 * s, height: 12 * s),
                                cornerRadius: 3 * s), with: ink, style: stroke)
                var lid = Path()
                lid.move(to: CGPoint(x: 9 * s, y: 7 * s)); lid.addLine(to: CGPoint(x: 10.3 * s, y: 4.6 * s))
                lid.addLine(to: CGPoint(x: 13.7 * s, y: 4.6 * s)); lid.addLine(to: CGPoint(x: 15 * s, y: 7 * s))
                ctx.stroke(lid, with: ink, style: stroke)
                ctx.stroke(Path(ellipseIn: CGRect(x: 8.8 * s, y: 9.8 * s, width: 6.4 * s, height: 6.4 * s)),
                           with: ink, style: stroke)
            case .library:
                ctx.stroke(Path(roundedRect: CGRect(x: 3 * s, y: 5 * s, width: 18 * s, height: 14 * s),
                                cornerRadius: 3 * s), with: ink, style: stroke)
                var hill = Path()
                hill.move(to: CGPoint(x: 5 * s, y: 16 * s)); hill.addLine(to: CGPoint(x: 10 * s, y: 11 * s))
                hill.addLine(to: CGPoint(x: 14 * s, y: 15 * s)); hill.addLine(to: CGPoint(x: 16.5 * s, y: 12.5 * s))
                hill.addLine(to: CGPoint(x: 19 * s, y: 15.5 * s))
                ctx.stroke(hill, with: ink, style: stroke)
            case .files:
                var doc = Path()
                doc.move(to: CGPoint(x: 6 * s, y: 3.5 * s)); doc.addLine(to: CGPoint(x: 14 * s, y: 3.5 * s))
                doc.addLine(to: CGPoint(x: 18.5 * s, y: 8 * s)); doc.addLine(to: CGPoint(x: 18.5 * s, y: 20.5 * s))
                doc.addLine(to: CGPoint(x: 6 * s, y: 20.5 * s)); doc.closeSubpath()
                ctx.stroke(doc, with: ink, style: stroke)
                var fold = Path()
                fold.move(to: CGPoint(x: 14 * s, y: 3.5 * s)); fold.addLine(to: CGPoint(x: 14 * s, y: 8 * s))
                fold.addLine(to: CGPoint(x: 18.5 * s, y: 8 * s))
                ctx.stroke(fold, with: ink, style: stroke)
            case .pulse:
                var p = Path()
                p.move(to: CGPoint(x: 2.5 * s, y: 12 * s)); p.addLine(to: CGPoint(x: 7 * s, y: 12 * s))
                p.addLine(to: CGPoint(x: 9 * s, y: 6.5 * s)); p.addLine(to: CGPoint(x: 12 * s, y: 17.5 * s))
                p.addLine(to: CGPoint(x: 14.5 * s, y: 12 * s)); p.addLine(to: CGPoint(x: 21.5 * s, y: 12 * s))
                ctx.stroke(p, with: ink, style: stroke)
            case .body:
                ctx.fill(Path(ellipseIn: CGRect(x: 10 * s, y: 3 * s, width: 4 * s, height: 4 * s)), with: ink)
                var b = Path()
                b.move(to: CGPoint(x: 12 * s, y: 8 * s)); b.addLine(to: CGPoint(x: 12 * s, y: 14 * s))
                b.move(to: CGPoint(x: 6 * s, y: 10 * s)); b.addLine(to: CGPoint(x: 18 * s, y: 10 * s))
                b.move(to: CGPoint(x: 12 * s, y: 14 * s)); b.addLine(to: CGPoint(x: 8 * s, y: 21 * s))
                b.move(to: CGPoint(x: 12 * s, y: 14 * s)); b.addLine(to: CGPoint(x: 16 * s, y: 21 * s))
                ctx.stroke(b, with: ink, style: stroke)
            }
        }
        .frame(width: 22, height: 22)
    }
}
