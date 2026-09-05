import SwiftUI

/// 06 · THE FIELD. Dave Whyte's breathing dots, after Matt Rossman's react-three-fiber
/// version, rewritten for this app's Canvas.
///
/// A hexagonally offset grid is pushed away from and pulled back toward the centre by a
/// ROUNDED SQUARE WAVE — `atan(sin(x)/delta)` — which sits at its extremes for most of the
/// cycle and snaps between them. A plain sine gives a gentle throb; this is what makes the
/// field look like it is holding a breath. Each dot's phase lags by its distance from the
/// centre, and that distance carries an octagonal offset (`cos(8θ)`), so the travelling ring
/// reads as a rotated square rather than a circle.
///
/// ⚠️ THE PULSE IS THE MEASUREMENT. `bpm` is the rate the band is reporting right now, and it
/// drives the wave directly: one breath per heartbeat. Nothing here is a decorative loop
/// running at a designer's tempo — when the band stops reporting, the field holds its last
/// rate and dims rather than inventing a rhythm. That is the whole reason it is on this
/// screen instead of a spinner.
///
/// The original's red/green/blue fringes come from compositing the previous two frames, one
/// colour channel each. That is a delay per *frame*, which halves on a 120 Hz screen. Here
/// the field is drawn three times in one pass, each copy trailing by a delay in SECONDS and
/// masked to one channel, blended additively: where all three land the channels sum back to
/// the dot colour, where only the leading copy has arrived you get the pure fringe.
struct BreathingDots: View {
    /// The band's current rate. nil means nothing has been reported yet: the field breathes
    /// at a slow resting tempo and says so by being dim, never by inventing a beat.
    var bpm: Int?
    /// 0…1 · how far into the measurement. Drives brightness and how far the field travels,
    /// so the screen visibly gathers rather than looping at one intensity for forty seconds.
    var intensity: Double = 1
    var tint: Color = NB.lime1
    /// Contact lost: the field freezes where it is and turns amber. It does not keep
    /// breathing on a wrist that is not being read.
    var held = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// ⚠️ The phase is ACCUMULATED, never computed from the clock. `now × rate` looks
    /// equivalent and is not: the epoch is 1.8 billion seconds, so a rate moving from 1.10 to
    /// 1.15 moves that product by ninety million cycles and the field jumps. Every reported
    /// beat changes the rate, so the jump was on every callback — the stutter. Accumulating
    /// dt × rate bends the tempo instead, which is what the original does and why it says so.
    @State private var clock = Phase()

    final class Phase {
        var cycles = 0.0
        var last: Date?
    }

    // MARK: the shape of the breath

    /// Rows of dots across the frame's height.
    /// ⚠️ Sized for the WHOLE SCREEN. At 30 — the figure from when this drew into a 240 pt
    /// box — a full-height phone gets 28 pt cells, and the field reads as a sparse polka dot
    /// rather than the original's fine mesh. The original runs 90 rows over a viewport; 52
    /// is as close as three lanes get while staying inside the ~3 700 ellipses a frame that
    /// the panel's own halftone screen already proves is affordable.
    private static let rows = 52.0
    /// Fraction of its own offset each dot travels at full intensity.
    private static let amplitude = 0.44
    /// Seconds of phase lag per unit of distance from the centre.
    /// ⚠️ This sets how MANY rings are in the air at once, and at a heartbeat's tempo the
    /// original's spacing puts three or four across the field — which reads as several
    /// patterns fighting rather than one thing breathing. Halved: one ring travelling out,
    /// the next just leaving the centre.
    private static let lag = 0.022
    /// Seconds between the three channel copies.
    /// ⚠️ The original runs this at about a frame (0.016 s) on a PINK base, where the three
    /// channels are close in strength and the fringe reads as a shimmer. Lime is (0.85, 0.95,
    /// 0.29): its blue lane is nearly black, so the same delay reads as separate red and
    /// green fields rather than a fringe on one lime one. Half a frame keeps the copies
    /// overlapping for most of the cycle and leaves the colour only on the moving edge.
    /// ⚠️ Also read as "two animations overlapping" at the earlier value: three copies far
    /// enough apart stop being a fringe on one field and become three fields. This is the
    /// edge-only setting; raise it for the original's louder separation.
    private static let chromaDelay = 0.007
    private static let restingBPM = 54.0

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || held)) { tl in
            Canvas(rendersAsynchronously: false) { ctx, size in
                draw(&ctx, size: size, at: tl.date)
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, at now: Date) {
        let unit = size.height / Self.rows          // world unit → points
        guard unit > 0.5 else { return }
        let cols = Int((size.width / unit).rounded(.up)) + 2
        let rows = Int(Self.rows.rounded(.up)) + 2
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)

        // One breath per heartbeat, and the rate the band last reported is what sets it.
        let rate = Double(bpm ?? Int(Self.restingBPM)) / 60
        var dt = clock.last.map { now.timeIntervalSince($0) } ?? 0
        clock.last = now
        // A backgrounded screen must not fast-forward the breath when it comes back.
        if !dt.isFinite || dt < 0 { dt = 0 }
        if dt > 0.05 { dt = 0.05 }
        clock.cycles = (clock.cycles + dt * rate).truncatingRemainder(dividingBy: 1)
        let t = clock.cycles
        let amp = Self.amplitude * (0.45 + 0.55 * min(1, max(0, intensity)))
        let radius = unit * 0.22

        let base = held ? NB.ember2 : tint
        let lanes: [(shift: Double, mask: (Double, Double, Double))] = [
            (0, (1, 0, 0)), (1, (0, 1, 0)), (2, (0, 0, 1)),
        ]

        for lane in lanes {
            var path = Path()
            let laneShift = lane.shift * Self.chromaDelay * rate
            for row in 0..<rows {
                for col in 0..<cols {
                    // Centred on the origin: the wave scales every dot about (0,0), so a grid
                    // whose middle sits half a cell off drifts as the field expands.
                    let x = Double(col) - Double(cols - 1) / 2
                    // Every other column nudged half a row down — the hexagonal packing that
                    // stops the field reading as a plain square lattice.
                    let y = Double(row) - Double(rows - 1) / 2 + (Double(col % 2) - 0.5) * 0.5
                    let len = (x * x + y * y).squareRoot()
                    // Unsigned angle from +X. Being unsigned mirrors the pattern about the X
                    // axis, and that mirroring is what closes the octagon — a signed angle
                    // here spirals instead.
                    let dirX = len > 1e-5 ? x / len : 1
                    let dist = len + cos(acos(min(1, max(-1, dirX))) * 8) * 0.5
                    // How square the wave is: small snaps, large rounds off. It grows with
                    // distance so the outer ranks ease into the turn while the middle cracks.
                    let delta = 0.15 + 0.2 * dist / 72
                    let phase = t - laneShift - dist * Self.lag * rate
                    let wave = (2 * amp / .pi) * atan(sin(2 * .pi * phase) / delta)
                    let scale = wave + 1.3
                    let px = centre.x + x * scale * unit
                    let py = centre.y + y * scale * unit
                    // Everything off the frame is skipped before it reaches the path: at the
                    // top of the breath a third of the grid is outside, and adding it costs
                    // the same as drawing it.
                    guard px > -radius, px < size.width + radius,
                          py > -radius, py < size.height + radius else { continue }
                    path.addEllipse(in: CGRect(x: px - radius, y: py - radius,
                                               width: radius * 2, height: radius * 2))
                }
            }
            // Additive, so the three copies sum back to the dot colour where they overlap and
            // leave a pure channel where only one has arrived.
            var layer = ctx
            layer.blendMode = .plusLighter
            let c = UIColor(base).rgb
            layer.fill(path, with: .color(Color(red: c.r * lane.mask.0,
                                                green: c.g * lane.mask.1,
                                                blue: c.b * lane.mask.2)
                .opacity(0.35 + 0.65 * min(1, max(0, intensity)))))
        }
    }
}

private extension UIColor {
    /// The three channels, so a lane can be masked down to one of them.
    var rgb: (r: Double, g: Double, b: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }
}
