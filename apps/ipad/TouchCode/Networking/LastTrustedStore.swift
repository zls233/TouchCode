import Foundation

/// Persists the last successfully connected host identifier for auto-connect.
/// Stored in UserDefaults for Phase 6a; future phases may move to secure storage.
final class LastTrustedStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "com.touchcode.lastTrustedHostID") {
        self.defaults = defaults
        self.key = key
    }

    func save(hostID: String) {
        defaults.set(hostID, forKey: key)
    }

    func load() -> String? {
        defaults.string(forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
