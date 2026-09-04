import Foundation

/// 06 · THE BALANCE READ. What a pulse study's beat-to-beat intervals say about which half of
/// the autonomic nervous system is doing more of the talking right now.
///
/// The whole computation is the Poincaré (Lorenz) plot of the interval series: every interval
/// against the one after it. The cloud that makes is described by two numbers —
///
///   SD1  the spread ACROSS the identity line: how much one beat differs from the next.
///        Beat-to-beat change is the vagus nerve's own signature, because it is the only
///        branch fast enough to act within a single beat. It tracks the parasympathetic side.
///   SD2  the spread ALONG it: the slower drift of the whole series over the run, which
///        carries sympathetic tone as well as breathing and posture.
///
/// The split below is SD1 against SD1+SD2. That is a RATIO OF SPREADS, not a measurement of
/// two nerves, and this file says so in the copy it produces.
///
/// ⚠️ NOT A DIAGNOSIS AND NOT A MEDICAL READING. It is the same wellness framing a training
/// watch uses for recovery. Nothing here names a condition, and nothing here should ever be
/// phrased as one — see `verdict`, which is written to describe a state and suggest nothing
/// clinical.
struct AutonomicBalance {
    /// Milliseconds. The mean of the intervals the band reported.
    let meanInterval: Double
    /// Beats a minute, from that mean. The band's own average is reported beside it, and
    /// when the two disagree the band's is the one shown — it saw every beat, this saw a
    /// sample of them.
    let beatsPerMinute: Int
    /// Milliseconds of spread across the identity line — the fast, beat-to-beat half.
    let sd1: Double
    /// Milliseconds of spread along it — the slow half.
    let sd2: Double
    /// SDNN, the plain standard deviation of the whole series, for the footer.
    let sdnn: Double
    /// 0…1 · SD1 / (SD1 + SD2). Above a half is a cloud dominated by beat-to-beat change.
    let parasympatheticShare: Double
    /// The points of the plot, as (x, y) pairs of consecutive intervals in milliseconds.
    let points: [(x: Double, y: Double)]

    var sympatheticShare: Double { 1 - parasympatheticShare }

    /// Which side is doing more of the talking, and by how much. `nil` when the two are
    /// close enough that naming a winner would be reading noise.
    enum Lead { case parasympathetic, sympathetic, even }

    var lead: Lead {
        // A ten-point margin either side of even. Below that the difference is smaller than
        // what a swallow or a change of posture moves in forty seconds.
        if parasympatheticShare > 0.55 { return .parasympathetic }
        if parasympatheticShare < 0.45 { return .sympathetic }
        return .even
    }

    /// ⚠️ Fewer than this many intervals and there is no cloud to describe — one swallow or
    /// one missed beat would swing the whole split. The screen says it could not read rather
    /// than printing a confident number from six points.
    static let minimumIntervals = 12

    /// Nil when the band reported too little to describe. Every caller draws the empty state
    /// rather than falling back to something plausible.
    init?(intervals: [Double]) {
        // Physiological range, at the outer bounds: 300 ms is 200 bpm, 2 000 ms is 30 bpm.
        // Anything outside is a dropped or doubled beat, and one of those in a forty-second
        // series moves SD1 more than the wearer's own state does.
        let clean = intervals.filter { $0 >= 300 && $0 <= 2000 }
        guard clean.count >= Self.minimumIntervals else { return nil }

        let mean = clean.reduce(0, +) / Double(clean.count)
        // Successive differences — the beat-to-beat half.
        let diffs = zip(clean.dropFirst(), clean).map(-)
        let sdsd = Self.standardDeviation(diffs)
        let sdnnValue = Self.standardDeviation(clean)

        // The standard Poincaré identities: the cloud is an ellipse whose minor axis is the
        // scatter of successive differences and whose major axis is what is left of the
        // total variance.
        let sd1Value = (0.5 * sdsd * sdsd).squareRoot()
        let sd2Value = max(0, 2 * sdnnValue * sdnnValue - 0.5 * sdsd * sdsd).squareRoot()

        meanInterval = mean
        beatsPerMinute = Int((60_000 / mean).rounded())
        sd1 = sd1Value
        sd2 = sd2Value
        sdnn = sdnnValue
        // Guarded: a perfectly regular series makes both zero, and the share of nothing is
        // not a half, it is undefined. Those series are already excluded by the count check
        // in practice, but a metronome-flat run must not divide by zero.
        parasympatheticShare = sd1Value + sd2Value > 0 ? sd1Value / (sd1Value + sd2Value) : 0.5
        points = zip(clean.dropLast(), clean.dropFirst()).map { (x: $0, y: $1) }
    }

    private static func standardDeviation(_ xs: [Double]) -> Double {
        guard xs.count > 1 else { return 0 }
        let mean = xs.reduce(0, +) / Double(xs.count)
        let variance = xs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(xs.count - 1)
        return variance.squareRoot()
    }

    // MARK: what it is allowed to say

    /// The headline. Describes the cloud, names no condition.
    var headline: String {
        switch lead {
        case .parasympathetic: L("Rest is leading.")
        case .sympathetic:     L("Drive is leading.")
        case .even:            L("Both sides, evenly.")
        }
    }

    /// One sentence under it. Written to describe a state and to be true of a forty-second
    /// sample — never advice, never a finding.
    /// ⚠️ Nothing in here may name a condition, suggest a treatment, or tell the reader what
    /// to do about their heart. That is the line between this and a medical device.
    var note: String {
        switch lead {
        case .parasympathetic:
            L("Your beat-to-beat spacing kept changing — the pattern a settled body makes. Forty seconds is a snapshot, not a verdict.")
        case .sympathetic:
            L("Your beats came at a steadier spacing, which is what effort, caffeine or a busy head all look like from here.")
        case .even:
            L("Neither half of the pattern is doing much more than the other right now.")
        }
    }

    /// The share as a percentage pair for the two bars.
    var split: (rest: Int, drive: Int) {
        let rest = Int((parasympatheticShare * 100).rounded())
        return (rest, 100 - rest)
    }
}
