import UIKit

/// Profile › REPORT A PROBLEM. One POST to the `feedback` Edge Function, which files a GitHub
/// issue on the product repo. The phone never sees the GitHub token; it sends words,
/// screenshots and enough about itself that nobody has to write back asking which build.
enum FeedbackReport {
    static let maxImages = 3

    struct Filed: Equatable {
        let number: Int
        let url: String
    }

    enum Outcome: Equatable {
        case filed(Filed)
        /// The server has no GitHub token yet — a deploy problem, not the user's.
        case unconfigured
        /// Five a minute is the budget; the sixth waits.
        case rateLimited
        /// Anything else: offline, 5xx, GitHub down. The form stays filled.
        case failed
    }

    /// A screenshot ready for the wire. 1280 px on the long side keeps a status bar and a
    /// chart label legible on the issue page; the byte cap keeps three of them inside one
    /// request. Unlike `AIImagePayload` this is not feeding a model, so it can afford detail.
    struct Image: Equatable {
        static let targetBytes = 600 * 1024
        let preview: UIImage
        let jpeg: Data

        static func prepare(_ raw: UIImage) -> Image? {
            let attempts: [(side: CGFloat, qualities: [CGFloat])] = [
                (1280, [0.72, 0.6, 0.5]),
                (960, [0.55, 0.45]),
                (720, [0.45]),
            ]
            var smallest: (UIImage, Data)?
            for attempt in attempts {
                let image = raw.nb_resized(maxSide: attempt.side)
                for q in attempt.qualities {
                    guard let data = image.jpegData(compressionQuality: q) else { continue }
                    if smallest == nil || data.count < smallest!.1.count { smallest = (image, data) }
                    if data.count <= targetBytes { return Image(preview: image, jpeg: data) }
                }
            }
            guard let smallest else { return nil }
            return Image(preview: smallest.0, jpeg: smallest.1)
        }
    }

    /// What the issue's facts table gets. No health data — the build, the phone, the band.
    static func context(band: BandState) -> [String: String] {
        let info = Bundle.main.infoDictionary ?? [:]
        var c: [String: String] = [
            "app": info["CFBundleShortVersionString"] as? String ?? "?",
            "build": info["CFBundleVersion"] as? String ?? "?",
            "ios": UIDevice.current.systemVersion,
            "device": hardwareModel(),
            "language": AppLanguage.shared.locale.rawValue,
            "timezone": TimeZone.current.identifier,
        ]
        if band.connected || !band.firmware.isEmpty {
            var parts = ["HOOP"]
            if !band.firmware.isEmpty { parts.append("fw \(band.firmware)") }
            parts.append(band.connected ? "connected" : "not connected")
            if let pct = band.batteryPercent { parts.append("\(pct)%") }
            c["band"] = parts.joined(separator: " · ")
        }
        return c
    }

    /// `iPhone17,2`, the identifier Apple's crash logs use — more useful to a maintainer
    /// than the marketing name, and it needs no lookup table that goes stale.
    private static func hardwareModel() -> String {
        var sys = utsname()
        uname(&sys)
        let mirror = Mirror(reflecting: sys.machine)
        let id = mirror.children.compactMap { $0.value as? Int8 }.prefix { $0 != 0 }.map { Character(UnicodeScalar(UInt8($0))) }
        let name = String(id)
        #if targetEnvironment(simulator)
        return "Simulator (\(ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? name))"
        #else
        return name
        #endif
    }

    static func send(title: String, body: String, images: [Image], band: BandState) async -> Outcome {
        let payload: [String: Any] = [
            "title": title,
            "body": body,
            "images": images.prefix(maxImages).map { ["mime": "image/jpeg", "base64": $0.jpeg.base64EncodedString()] },
            "context": context(band: band),
        ]
        do {
            let row = try await SupabaseClient.shared.callFunction("feedback", payload: payload)
            guard let number = row["number"] as? Int, let url = row["url"] as? String else { return .failed }
            await Analytics.shared.track("FEEDBACK_FILED", ["NUMBER": number, "IMAGES": images.count])
            return .filed(Filed(number: number, url: url))
        } catch SupabaseFailure.http(let code, let text) {
            if code == 429 { return .rateLimited }
            if code == 503, text.contains("FEEDBACK_UNCONFIGURED") { return .unconfigured }
            return .failed
        } catch {
            return .failed
        }
    }
}
