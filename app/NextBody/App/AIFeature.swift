import Foundation

/// Every AI surface in the app lives under `NextBody/AI/` and is reached only through a
/// check on this switch: the dock's keyboard and hold-to-talk, Chat, the plan face, AI
/// memory, meal photo estimates and the Shot widget. Off, Home is the panel, the strip and
/// the plus key; nothing calls `/turn`, `/asr` or `memory-settle`.
///
/// The server keeps its own switch (`AI_ENABLED`), so an old build cannot reach the model
/// either.
enum AIFeature {
    static let enabled = false
}
