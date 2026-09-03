import Foundation

/// One sport the band can be asked to open. Raw values are `VPDeviceRuningMode` ordinals
/// in the SDK header's own order. The product list stops at Dumbbell (#47) — that is the
/// set Device's DEBUG probe already enumerates, not the full enum (100+).
struct SportModeOption: Identifiable, Hashable {
    var id: Int { rawValue }
    let rawValue: Int
    let name: String
}

enum SportModeCatalog {
    static let modes: [SportModeOption] = [
        .init(rawValue: 0, name: "Common"),
        .init(rawValue: 1, name: "Outdoor run"),
        .init(rawValue: 2, name: "Outdoor walk"),
        .init(rawValue: 3, name: "Indoor run"),
        .init(rawValue: 4, name: "Indoor walk"),
        .init(rawValue: 5, name: "Hiking"),
        .init(rawValue: 6, name: "Stair stepper"),
        .init(rawValue: 7, name: "Outdoor cycle"),
        .init(rawValue: 8, name: "Stationary bike"),
        .init(rawValue: 9, name: "Elliptical"),
        .init(rawValue: 10, name: "Rowing machine"),
        .init(rawValue: 11, name: "Mountaineering"),
        .init(rawValue: 12, name: "Swim"),
        .init(rawValue: 13, name: "Sit-ups"),
        .init(rawValue: 14, name: "Ski"),
        .init(rawValue: 15, name: "Jump rope"),
        .init(rawValue: 16, name: "Yoga"),
        .init(rawValue: 17, name: "Table tennis"),
        .init(rawValue: 18, name: "Basketball"),
        .init(rawValue: 19, name: "Volleyball"),
        .init(rawValue: 20, name: "Football"),
        .init(rawValue: 21, name: "Badminton"),
        .init(rawValue: 22, name: "Tennis"),
        .init(rawValue: 23, name: "Stair climb"),
        .init(rawValue: 24, name: "Fitness"),
        .init(rawValue: 25, name: "Weightlifting"),
        .init(rawValue: 26, name: "Diving"),
        .init(rawValue: 27, name: "Boxing"),
        .init(rawValue: 28, name: "Gym ball"),
        .init(rawValue: 29, name: "Squat training"),
        .init(rawValue: 30, name: "Triathlon"),
        .init(rawValue: 31, name: "Dance"),
        .init(rawValue: 32, name: "HIIT"),
        .init(rawValue: 33, name: "Rock climbing"),
        .init(rawValue: 34, name: "Sports"),
        .init(rawValue: 35, name: "Balls"),
        .init(rawValue: 36, name: "Fitness game"),
        .init(rawValue: 37, name: "Free time"),
        .init(rawValue: 38, name: "Aerobics"),
        .init(rawValue: 39, name: "Gymnastics"),
        .init(rawValue: 40, name: "Floor exercise"),
        .init(rawValue: 41, name: "Horizontal bar"),
        .init(rawValue: 42, name: "Parallel bars"),
        .init(rawValue: 43, name: "Trampoline"),
        .init(rawValue: 44, name: "Track & field"),
        .init(rawValue: 45, name: "Marathon"),
        .init(rawValue: 46, name: "Push-ups"),
        .init(rawValue: 47, name: "Dumbbell"),
    ]

    static func name(for rawValue: Int) -> String {
        modes.first(where: { $0.rawValue == rawValue })?.name ?? "Sport #\(rawValue)"
    }
}
