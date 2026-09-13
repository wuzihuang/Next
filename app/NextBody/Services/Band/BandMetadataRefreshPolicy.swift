import Foundation

/// Process-local: each new app process initializes once, not every health-data pull.
/// Only confirmed publication can be reused, and never for another ownership row/firmware.
struct BandMetadataRefreshPolicy {
    struct Key: Equatable {
        let account: String
        let binding: String
        let deviceID: String
        let firmware: String
    }
    private var confirmed: Key?

    func needsRefresh(_ key: Key?) -> Bool { key == nil || key != confirmed }
    mutating func complete(_ key: Key?, success: Bool) {
        if success { confirmed = key }
    }
}
