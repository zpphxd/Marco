import Foundation

// MARK: - Landmark Sighting (shared between mesh and landmarks)

struct LandmarkSighting: Codable, Hashable {
    let landmarkID: String
    let rssi: Int
}

// MARK: - Mesh Message Types

struct MeshSearch: Codable {
    let id: String
    let queryHash: String
    let originID: String
    var ttl: Int
    var hopCount: Int
    let timestamp: TimeInterval
    var path: [String]

    static func create(queryHash: String, originID: String, ttl: Int = 4) -> MeshSearch {
        MeshSearch(
            id: UUID().uuidString,
            queryHash: queryHash,
            originID: originID,
            ttl: ttl,
            hopCount: 0,
            timestamp: Date().timeIntervalSince1970,
            path: []
        )
    }
}

struct MeshFound: Codable {
    let id: String
    let searchID: String
    let queryHash: String
    let originID: String
    var hopCount: Int
    let rssiAtFind: Int
    let landmarks: [LandmarkSighting]?
    var returnPath: [String]

    static func create(search: MeshSearch, rssi: Int, landmarks: [LandmarkSighting]?) -> MeshFound {
        MeshFound(
            id: UUID().uuidString,
            searchID: search.id,
            queryHash: search.queryHash,
            originID: search.originID,
            hopCount: 0,
            rssiAtFind: rssi,
            landmarks: landmarks,
            returnPath: search.path.reversed()
        )
    }
}

struct MeshBeacon: Codable {
    let senderHash: String
    let landmarks: [LandmarkSighting]
    let timestamp: TimeInterval
}

// MARK: - Envelope for transport

enum MeshMessageType: String, Codable {
    case search
    case found
    case beacon
}

struct MeshEnvelope: Codable {
    let type: MeshMessageType
    let payload: Data

    static func wrap(_ search: MeshSearch) -> Data? {
        guard let payload = try? JSONEncoder().encode(search) else { return nil }
        let envelope = MeshEnvelope(type: .search, payload: payload)
        return try? JSONEncoder().encode(envelope)
    }

    static func wrap(_ found: MeshFound) -> Data? {
        guard let payload = try? JSONEncoder().encode(found) else { return nil }
        let envelope = MeshEnvelope(type: .found, payload: payload)
        return try? JSONEncoder().encode(envelope)
    }

    static func wrap(_ beacon: MeshBeacon) -> Data? {
        guard let payload = try? JSONEncoder().encode(beacon) else { return nil }
        let envelope = MeshEnvelope(type: .beacon, payload: payload)
        return try? JSONEncoder().encode(envelope)
    }

    func unwrapSearch() -> MeshSearch? {
        guard type == .search else { return nil }
        return try? JSONDecoder().decode(MeshSearch.self, from: payload)
    }

    func unwrapFound() -> MeshFound? {
        guard type == .found else { return nil }
        return try? JSONDecoder().decode(MeshFound.self, from: payload)
    }

    func unwrapBeacon() -> MeshBeacon? {
        guard type == .beacon else { return nil }
        return try? JSONDecoder().decode(MeshBeacon.self, from: payload)
    }
}
