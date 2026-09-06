import Foundation

/// Paper 04D · the plan face is assembled on the phone from settled numbers.
/// No `/turn`. A missing night stays missing — the page does not invent a score.
public enum PlanFaceMath {
    public static let cycleSeconds = 2.4
    public static let travel = 6.4
    public static let fadeIn = 0.24
    public static let fadeOut = 0.30
    public static let openThreshold = 40.0
    public static let flingSpeed = 300.0
    public static let idleDelay = 3.0
    public static let maxCycles = 6
    /// The lip is 36pt. The hit slop reaches above it so a swipe does not start
    /// on the Home Indicator, which iOS keeps for itself.
    public static let lipHotZone = 80.0
    public static let earliestBedOffset = 180.0
    public static let bedPullback = 45.0
    public static let dash = "——"

    public enum Group: String, CaseIterable, Sendable {
        case recovery, regularity, architecture, duration
    }

    public enum ActionKind: String, CaseIterable, Sendable {
        case bed, load, strength, meal, quiet
    }

    /// The catalog is always these five rows, even when a value is still a dash.
    public static let catalog: [ActionKind] = [.bed, .load, .strength, .meal, .quiet]

    public struct Night: Equatable, Sendable {
        public var score: Int
        public var duration: Int?
        public var architecture: Int?
        public var recovery: Int?
        public var regularity: Int?
        public var personalWeight: Double
        public var hrvMs: Double?
        public var bedOffset: Double?
        public var nightIndex: Int

        public init(score: Int, duration: Int?, architecture: Int?, recovery: Int?,
                    regularity: Int?, personalWeight: Double, hrvMs: Double?,
                    bedOffset: Double?, nightIndex: Int) {
            self.score = score
            self.duration = duration
            self.architecture = architecture
            self.recovery = recovery
            self.regularity = regularity
            self.personalWeight = personalWeight
            self.hrvMs = hrvMs
            self.bedOffset = bedOffset
            self.nightIndex = nightIndex
        }

        public func value(of group: Group) -> Int? {
            switch group {
            case .recovery:     recovery
            case .regularity:   regularity
            case .architecture: architecture
            case .duration:     duration
            }
        }
    }

    public struct Load: Equatable, Sendable {
        public var yesterday: Double?
        public var dayBefore: Double?
        public var target: Double?
        public var activeMinutes: Int?

        public init(yesterday: Double?, dayBefore: Double?, target: Double?, activeMinutes: Int?) {
            self.yesterday = yesterday
            self.dayBefore = dayBefore
            self.target = target
            self.activeMinutes = activeMinutes
        }
    }

    public struct Action: Equatable, Sendable {
        public var kind: ActionKind
        public var trailing: String
        public var bedClock: String?
        public var minutesLate: Int?
        public var regularity: Int?
        public var yesterday: Double?
        public var dayBefore: Double?
        public var target: Double?

        public init(kind: ActionKind, trailing: String, bedClock: String? = nil,
                    minutesLate: Int? = nil, regularity: Int? = nil,
                    yesterday: Double? = nil, dayBefore: Double? = nil,
                    target: Double? = nil) {
            self.kind = kind
            self.trailing = trailing
            self.bedClock = bedClock
            self.minutesLate = minutesLate
            self.regularity = regularity
            self.yesterday = yesterday
            self.dayBefore = dayBefore
            self.target = target
        }
    }

    public struct Read: Equatable, Sendable {
        public var kind: String
        public var grain: String
        public var value: String

        public init(kind: String, grain: String, value: String) {
            self.kind = kind
            self.grain = grain
            self.value = value
        }
    }

    public struct Face: Equatable, Sendable {
        public var empty: Bool
        public var weakest: Group?
        public var score: Int?
        public var night: Night?
        public var load: Load
        public var mealsLogged: Bool
        public var actions: [Action]
        public var reads: [Read]
        public var generatedClock: String
        public var scoredNightCount: Int
        public var readyFrom: String?
        public var readyTo: String?

        public init(empty: Bool, weakest: Group?, score: Int?, night: Night?,
                    load: Load, mealsLogged: Bool, actions: [Action], reads: [Read],
                    generatedClock: String, scoredNightCount: Int,
                    readyFrom: String?, readyTo: String?) {
            self.empty = empty
            self.weakest = weakest
            self.score = score
            self.night = night
            self.load = load
            self.mealsLogged = mealsLogged
            self.actions = actions
            self.reads = reads
            self.generatedClock = generatedClock
            self.scoredNightCount = scoredNightCount
            self.readyFrom = readyFrom
            self.readyTo = readyTo
        }
    }

    public static func phase(_ t: Double, offset k: Double) -> Double {
        let x = t + k
        return x - floor(x)
    }

    /// `y(p) = 3.2 − 6.4·p`. Up is negative. Down inverts it.
    public static func offsetY(phase p: Double, up: Bool) -> Double {
        let y = 3.2 - travel * p
        return up ? y : -y
    }

    public static func alpha(phase p: Double) -> Double {
        min(p / fadeIn, 1) * min((1 - p) / fadeOut, 1)
    }

    public static func flatten(translation: Double) -> Double {
        min(1, max(0, abs(translation) / openThreshold))
    }

    public static func idlePlaying(elapsed: Double, openedThisLaunch: Bool,
                                   reduceMotion: Bool) -> Bool {
        guard !openedThisLaunch, !reduceMotion else { return false }
        return elapsed >= idleDelay && elapsed < idleDelay + Double(maxCycles) * cycleSeconds
    }

    /// The lip chase is the arrow's resting motion. Opening the plan does
    /// not retire it — Reduce Motion is the only stop.
    public static func hintPlaying(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    public static func shouldCommit(translation: Double, velocity: Double,
                                    opening: Bool) -> Bool {
        if opening {
            return translation <= -openThreshold || velocity <= -flingSpeed
        }
        return translation >= openThreshold || velocity >= flingSpeed
    }

    /// `bed_offset` is minutes past 18:00 local. Same unwind as the sleep board.
    public static func bedClock(offset: Double) -> String {
        let minutes = ((Int(offset.rounded()) + 1080) % 1440 + 1440) % 1440
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    public static func suggestedBed(offset: Double) -> (clock: String, minutesLate: Int) {
        let earlier = max(earliestBedOffset, offset - bedPullback)
        let late = max(0, Int((offset - earlier).rounded()))
        return (bedClock(offset: earlier), late)
    }

    public static func weighted(_ score: Int?, weight: Int) -> Int? {
        score.map { Int((Double($0) * Double(weight) / 100).rounded()) }
    }

    public static func loadLabel(_ value: Double?) -> String {
        guard let value else { return dash }
        return String(format: "%.1f", min(value, 20.9))
    }

    public static func clock(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }

    public static func weakest(of night: Night) -> Group? {
        var best: (Group, Int)?
        for group in Group.allCases {
            guard let value = night.value(of: group) else { continue }
            if best == nil || value < best!.1 { best = (group, value) }
        }
        return best?.0
    }

    public static func face(night: Night?, load: Load, mealsLogged: Bool,
                            scoredNightCount: Int, readyFrom: String?,
                            readyTo: String?, now: Date) -> Face {
        let empty = night == nil
        let weakest = night.flatMap(weakest(of:))
        let bed: Action = {
            if let night, let offset = night.bedOffset {
                let suggested = suggestedBed(offset: offset)
                return Action(kind: .bed, trailing: suggested.clock, bedClock: suggested.clock,
                              minutesLate: suggested.minutesLate, regularity: night.regularity)
            }
            return Action(kind: .bed, trailing: dash)
        }()
        let loadAction = Action(
            kind: .load,
            trailing: load.target != nil || load.yesterday != nil ? loadLabel(load.target) : dash,
            yesterday: load.yesterday, dayBefore: load.dayBefore, target: load.target)
        let strengthOn = weakest == .recovery || (load.yesterday ?? 0) >= 10
        let strength = Action(kind: .strength, trailing: strengthOn ? "RUN TOMORROW" : dash)
        let meal = Action(kind: .meal, trailing: mealsLogged ? "LOGGED" : "UNLOGGED")
        let quiet = Action(kind: .quiet, trailing: "16:00")
        let actions = [bed, loadAction, strength, meal, quiet]

        let reads: [Read] = [
            Read(kind: "score",
                 grain: scoredNightCount > 0 ? "\(scoredNightCount) NIGHTS" : dash,
                 value: scoreRead(night)),
            Read(kind: "hrv",
                 grain: "30 MIN BUCKET",
                 value: hrvRead(night)),
            Read(kind: "load",
                 grain: "DAILY",
                 value: loadRead(load)),
            Read(kind: "active",
                 grain: "DERIVED",
                 value: load.activeMinutes.map { "\($0) MIN" } ?? dash),
        ]

        return Face(
            empty: empty,
            weakest: weakest,
            score: night?.score,
            night: night,
            load: load,
            mealsLogged: mealsLogged,
            actions: actions,
            reads: reads,
            generatedClock: clock(now),
            scoredNightCount: scoredNightCount,
            readyFrom: readyFrom,
            readyTo: readyTo)
    }

    private static func scoreRead(_ night: Night?) -> String {
        guard let night else { return dash }
        if let recovery = weighted(night.recovery, weight: 35) {
            return "\(night.score) · REC \(recovery)/35"
        }
        return "\(night.score)"
    }

    private static func hrvRead(_ night: Night?) -> String {
        guard let ms = night?.hrvMs else { return dash }
        let value = "\(Int(ms.rounded())) MS"
        guard let index = night?.nightIndex, index > 0 else { return value }
        return "\(value) · NIGHT \(index)"
    }

    private static func loadRead(_ load: Load) -> String {
        let parts = [load.yesterday, load.dayBefore].map(loadLabel)
        if parts.allSatisfy({ $0 == dash }) { return dash }
        return parts.joined(separator: " · ") + " · CAP 21"
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
