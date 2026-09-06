import Foundation
import os
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The App Group copy of today's three numbers.
///
/// The widget cannot talk to the band. It only paints this glance. `.standard`
/// is never a fallback — that would give the app and the extension two stores,
/// and TODAY would stay empty on a real home screen.
enum WidgetBridge {
    static let suiteName = "group.com.nextbody.hoop"
    static let todayKind = "NextBodyToday"
    static let shotKind = "NextBodyShot"
    static let photoURL = URL(string: "nextbody://log?via=photo")!
    static let photoDidArrive = Notification.Name("NextBody.widgetPhoto")
    private static let pendingPhotoKey = "widget.shot.pending"
    private static let glanceKey = "widget.glance.v1"
    private static let glanceFile = "widget.glance.v1.json"
    private static let log = Logger(subsystem: "com.nextbody.hoop", category: "widget")

    private static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName)
    }

    private static var defaults: UserDefaults? {
        guard container != nil else { return nil }
        return UserDefaults(suiteName: suiteName)
    }

    private static var glanceURL: URL? {
        container?.appendingPathComponent(glanceFile)
    }

    static func loadGlance() -> WidgetFaceMath.Glance? {
        if let url = glanceURL, let data = try? Data(contentsOf: url),
           let glance = try? JSONDecoder().decode(WidgetFaceMath.Glance.self, from: data) {
            return glance
        }
        guard let data = defaults?.data(forKey: glanceKey) else { return nil }
        return try? JSONDecoder().decode(WidgetFaceMath.Glance.self, from: data)
    }

    static func save(_ glance: WidgetFaceMath.Glance) {
        guard let data = try? JSONEncoder().encode(glance) else { return }
        let previous = loadGlance()
        guard write(data) else { return }
        if previous != glance { reload() }
    }

    static func clear() {
        if let url = glanceURL { try? FileManager.default.removeItem(at: url) }
        defaults?.removeObject(forKey: glanceKey)
        reload()
    }

    static func reload() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: todayKind)
        #endif
    }

    static func isPhotoLog(_ url: URL) -> Bool {
        guard url.scheme == "nextbody", url.host == "log" else { return false }
        let via = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "via" })?.value
        return via == "photo"
    }

    static func rememberPhoto() {
        UserDefaults.standard.set(true, forKey: pendingPhotoKey)
    }

    static func consumePhoto() -> Bool {
        guard UserDefaults.standard.bool(forKey: pendingPhotoKey) else { return false }
        UserDefaults.standard.removeObject(forKey: pendingPhotoKey)
        return true
    }

    @discardableResult
    private static func write(_ data: Data) -> Bool {
        guard container != nil else {
            log.error("app group \(suiteName, privacy: .public) is not available")
            return false
        }
        if let url = glanceURL {
            do { try data.write(to: url, options: .atomic) }
            catch {
                log.error("glance file write failed")
                return false
            }
        }
        defaults?.set(data, forKey: glanceKey)
        return true
    }
}
