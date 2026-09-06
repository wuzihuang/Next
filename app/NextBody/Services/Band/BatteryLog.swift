import Foundation

/// One reading the phone actually heard from the band — percent or bars, charge
/// state, and whether the link was up. The device page's trend is this log, not a
/// guessed drain curve.
struct BatteryObservation: Equatable, Sendable, Codable {
    var at: Date
    var isPercent: Bool
    var percent: Int?
    var level: Int?
    var charge: Charge
    var connected: Bool

    enum Charge: String, Codable, Sendable, Equatable {
        case unplugged, charging, full, unknown
    }

    /// What the chart plots. A bar count stays a bar count — it is never multiplied into %.
    var plotValue: Double? {
        if isPercent { return percent.map(Double.init) }
        return level.map(Double.init)
    }
}

struct BatteryPoint: Equatable, Sendable {
    var at: Date
    var value: Double
    var charge: BatteryObservation.Charge
}

struct BatterySpan: Equatable, Sendable {
    var start: Date
    var end: Date
}

struct BatteryPlot: Equatable, Sendable {
    var runs: [[BatteryPoint]]
    var charging: [BatterySpan]
    var isPercent: Bool
    var yMax: Double
    var high: Double?
    var low: Double?
    var start: Date
    var end: Date

    var points: [BatteryPoint] { runs.flatMap { $0 } }
}

/// Record every real battery event, skip chatter, keep plateaus, and draw the line
/// the device page shows after a tap on the ring.
enum BatteryLog {
    static let plateau: TimeInterval = 30 * 60
    /// Long enough for the month window. Older rows fall off on the next record.
    static let keep: TimeInterval = 30 * 24 * 3600
    static let cap = 2000
    static let windowDays = 7

    static func window(endingAt now: Date, days: Int = windowDays) -> (start: Date, end: Date) {
        (now.addingTimeInterval(-Double(days) * 24 * 3600), now)
    }

    static func window(endingAt now: Date, range: RollingPills) -> (start: Date, end: Date) {
        let hours = DetailWindow(.battery, range).hours
        return (now.addingTimeInterval(-Double(hours) * 3600), now)
    }

    static func record(
        _ existing: [BatteryObservation],
        at: Date,
        isPercent: Bool,
        percent: Int?,
        level: Int?,
        charge: BatteryObservation.Charge,
        connected: Bool
    ) -> [BatteryObservation] {
        let incoming = BatteryObservation(
            at: at, isPercent: isPercent, percent: percent, level: level,
            charge: charge, connected: connected)
        var samples = existing
            .filter { at.timeIntervalSince($0.at) <= keep }
            .sorted { $0.at < $1.at }
        if let last = samples.last {
            let same = last.isPercent == incoming.isPercent
                && last.percent == incoming.percent
                && last.level == incoming.level
                && last.charge == incoming.charge
                && last.connected == incoming.connected
            let dt = incoming.at.timeIntervalSince(last.at)
            if same && dt >= 0 && dt < plateau { return samples }
            if incoming.at < last.at { return samples }
        }
        samples.append(incoming)
        if samples.count > cap { samples = Array(samples.suffix(cap)) }
        return samples
    }

    static func plot(
        _ samples: [BatteryObservation],
        from start: Date,
        to end: Date
    ) -> BatteryPlot {
        let ordered = samples.sorted { $0.at < $1.at }
        var series: [BatteryObservation] = []
        if let carry = ordered.last(where: { $0.at < start }) {
            var edge = carry
            edge.at = start
            series.append(edge)
        }
        series.append(contentsOf: ordered.filter { $0.at >= start && $0.at <= end })

        // Only a sample that carries a value gets a vote. Connect/disconnect rows have no
        // reading in them and must not decide whether this band speaks percent or bars.
        let valued = series.filter { $0.plotValue != nil }
        let percented = valued.filter(\.isPercent).count
        let isPercent = percented >= valued.count - percented

        var runs: [[BatteryPoint]] = []
        var run: [BatteryPoint] = []
        var charging: [BatterySpan] = []
        var chargeStart: Date?
        var lastConnected: BatteryPoint?

        func flushRun() {
            if !run.isEmpty { runs.append(run); run = [] }
        }
        func closeCharge(at date: Date) {
            if let started = chargeStart, date > started {
                charging.append(BatterySpan(start: started, end: date))
            }
            chargeStart = nil
        }

        for sample in series {
            if !sample.connected {
                closeCharge(at: sample.at)
                flushRun()
                lastConnected = nil
                continue
            }
            guard let value = sample.plotValue else { continue }
            // A bar count is not a percentage. A sample in the other unit cannot share this
            // ruler — plotted on it, 3 bars would draw as 3 % — so the line breaks instead.
            guard sample.isPercent == isPercent else {
                flushRun()
                lastConnected = nil
                continue
            }
            let point = BatteryPoint(at: sample.at, value: value, charge: sample.charge)
            run.append(point)
            lastConnected = point
            if sample.charge == .charging {
                if chargeStart == nil { chargeStart = sample.at }
            } else {
                closeCharge(at: sample.at)
            }
        }
        if let last = lastConnected {
            // The span runs to the edge of the window whether or not the last reading landed
            // before it: a band charging right now must still be shaded as charging.
            if last.at < end {
                run.append(BatteryPoint(at: end, value: last.value, charge: last.charge))
            }
            if chargeStart != nil { closeCharge(at: end) }
        } else {
            chargeStart = nil
        }
        flushRun()

        let values = runs.flatMap { $0 }.map(\.value)
        return BatteryPlot(
            runs: runs,
            charging: charging,
            isPercent: isPercent,
            yMax: isPercent ? 100 : 4,
            high: values.max(),
            low: values.min(),
            start: start,
            end: end)
    }

    /// Simulator walk-through: a month of overnight charges, then three closer days
    /// with a disconnect, ending on `percent`.
    static func seed(now: Date, percent: Int = 82) -> [BatteryObservation] {
        func row(_ hoursAgo: Double, _ value: Int, _ charge: BatteryObservation.Charge,
                 connected: Bool = true) -> BatteryObservation {
            BatteryObservation(
                at: now.addingTimeInterval(-hoursAgo * 3600),
                isPercent: true, percent: value, level: nil,
                charge: charge, connected: connected)
        }
        var rows: [BatteryObservation] = []
        for day in stride(from: 29, through: 4, by: -1) {
            let base = Double(day) * 24
            let trough = 28 + (day % 5) * 6
            rows.append(row(base + 18, max(22, trough - 8), .unplugged))
            if day % 6 == 0 {
                rows.append(row(base + 10, max(18, trough - 16), .unplugged))
                if day == 12 {
                    rows.append(row(base + 9, max(18, trough - 16), .unplugged, connected: false))
                    rows.append(row(base + 8.5, max(18, trough - 16), .unplugged))
                }
            } else {
                rows.append(row(base + 16, trough, .unplugged))
                rows.append(row(base + 15.95, trough, .charging))
                rows.append(row(base + 11, 100, .full))
                rows.append(row(base + 10.95, 100, .unplugged))
            }
            rows.append(row(base + 4, 78 + (day % 3) * 4, .unplugged))
        }
        rows.append(contentsOf: [
            row(70, 100, .full),
            row(69.9, 100, .unplugged),
            row(64, 88, .unplugged),
            row(58, 72, .unplugged),
            row(52, 55, .unplugged),
            row(48, 40, .unplugged),
            row(47.9, 40, .charging),
            row(44, 70, .charging),
            row(40, 100, .full),
            row(39.9, 100, .unplugged),
            row(34, 86, .unplugged),
            row(28, 68, .unplugged),
            row(26, 68, .unplugged, connected: false),
            row(25.5, 68, .unplugged),
            row(22, 48, .unplugged),
            row(21.9, 48, .charging),
            row(16, 85, .charging),
            row(14, 100, .full),
            row(13.9, 100, .unplugged),
            row(8, 94, .unplugged),
            row(4, 88, .unplugged),
            row(0, percent, .unplugged),
        ])
        return rows.sorted { $0.at < $1.at }
    }

    /// Last time the band reported it was on a charger. Pass a window when the
    /// number belongs to one range; omit it for the device page's lifetime stamp.
    static func lastPlug(in samples: [BatteryObservation], from start: Date? = nil, to end: Date? = nil) -> Date? {
        samples.last { sample in
            guard sample.charge == .charging else { return false }
            if let start, sample.at < start { return false }
            if let end, sample.at > end { return false }
            return true
        }?.at
    }

    /// Last time the phone had the link. A connected sample counts, including
    /// the one that is still live.
    static func lastLink(in samples: [BatteryObservation]) -> Date? {
        samples.last(where: \.connected)?.at
    }
}

enum BatteryLogStore {
    static func key(_ owner: String) -> String { "nb.battery.log.\(owner)" }

    static func load(owner: String, defaults: UserDefaults = .standard) -> [BatteryObservation] {
        guard !owner.isEmpty,
              let data = defaults.data(forKey: key(owner)) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([BatteryObservation].self, from: data)) ?? []
    }

    static func save(_ samples: [BatteryObservation], owner: String,
                     defaults: UserDefaults = .standard) {
        guard !owner.isEmpty else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        defaults.set(try? encoder.encode(samples), forKey: key(owner))
    }
}
