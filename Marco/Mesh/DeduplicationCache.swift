import Foundation

actor DeduplicationCache {
    private struct Entry {
        let id: String
        let expiry: Date
    }

    private var entries: [String: Entry] = [:]
    private let ttl: TimeInterval
    private let maxCapacity: Int

    init(ttl: TimeInterval = 60, maxCapacity: Int = 2048) {
        self.ttl = ttl
        self.maxCapacity = maxCapacity
    }

    /// Returns true if this message ID has NOT been seen (should be processed).
    /// Inserts it into the cache.
    func shouldProcess(_ id: String) -> Bool {
        cleanup()

        if entries[id] != nil {
            return false
        }

        // Evict oldest if at capacity
        if entries.count >= maxCapacity {
            let oldest = entries.min { $0.value.expiry < $1.value.expiry }
            if let oldestKey = oldest?.key {
                entries.removeValue(forKey: oldestKey)
            }
        }

        entries[id] = Entry(id: id, expiry: Date().addingTimeInterval(ttl))
        return true
    }

    private func cleanup() {
        let now = Date()
        entries = entries.filter { $0.value.expiry > now }
    }
}
