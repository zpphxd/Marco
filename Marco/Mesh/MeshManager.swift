import Foundation
import MultipeerConnectivity

protocol MeshManagerDelegate: AnyObject {
    func meshManager(_ manager: MeshManager, didFindContact name: String, hash: String, hopCount: Int, rssiAtFind: Int, landmarks: [LandmarkSighting]?)
    func meshManager(_ manager: MeshManager, didRelaySearch hash: String, hops: Int)
    func meshManager(_ manager: MeshManager, didReceiveBeacon senderHash: String, landmarks: [LandmarkSighting])
}

extension MeshManagerDelegate {
    func meshManager(_ manager: MeshManager, didReceiveBeacon senderHash: String, landmarks: [LandmarkSighting]) {}
}

@MainActor
class MeshManager: NSObject, ObservableObject {
    @Published var connectedPeers: Int = 0
    @Published var searchesRelayed: Int = 0
    @Published var foundResponses: Int = 0
    @Published var isActive = false

    weak var delegate: MeshManagerDelegate?

    private let serviceType = "marco-mesh"
    private let myPeerID: MCPeerID
    private var session: MCSession?
    nonisolated(unsafe) private var _session: MCSession? // non-isolated access for MPC delegates
    private var browser: MCNearbyServiceBrowser?
    private var advertiser: MCNearbyServiceAdvertiser?

    private let dedup = DeduplicationCache()
    private var routingTable: [String: MCPeerID] = [:] // originID → peer that sent it
    private var myOriginIDs: Set<String> = [] // our own search origin IDs

    private var myHash: String
    private let contactManager: ContactHashManager
    private var landmarkProvider: (() -> [LandmarkSighting])?

    // Rate limiting
    private var forwardCount = 0
    private var forwardWindowStart = Date()
    private let maxForwardsPerSecond = 20

    init(myHash: String, contactManager: ContactHashManager) {
        self.myHash = myHash
        self.contactManager = contactManager
        self.myPeerID = MCPeerID(displayName: UUID().uuidString.prefix(8).description)
        super.init()
    }

    func setLandmarkProvider(_ provider: @escaping () -> [LandmarkSighting]) {
        landmarkProvider = provider
    }

    func updateMyHash(_ hash: String) {
        myHash = hash
    }

    func start() {
        guard !isActive else { return }

        let session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .none)
        session.delegate = self
        self.session = session
        self._session = session

        let browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser

        let advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser

        isActive = true
        print("[Mesh] Started — peer: \(myPeerID.displayName)")
    }

    func stop() {
        browser?.stopBrowsingForPeers()
        advertiser?.stopAdvertisingPeer()
        session?.disconnect()
        browser = nil
        advertiser = nil
        session = nil
        _session = nil
        isActive = false
        connectedPeers = 0
        routingTable.removeAll()
        myOriginIDs.removeAll()
        print("[Mesh] Stopped")
    }

    // MARK: - Send Search

    func searchForHash(_ hash: String) {
        let originID = UUID().uuidString
        myOriginIDs.insert(originID)

        let search = MeshSearch.create(queryHash: hash, originID: originID)
        broadcast(search)
        print("[Mesh] Searching for \(hash) with origin \(originID.prefix(8))")
    }

    // MARK: - Beacon (landmark fingerprint exchange)

    func broadcastBeacon() {
        guard let session = session else {
            print("[Mesh] Beacon skip: no session")
            return
        }
        guard !session.connectedPeers.isEmpty else {
            // Only log occasionally to avoid spam
            return
        }
        let landmarks = landmarkProvider?() ?? []
        guard !landmarks.isEmpty else { return }

        let beacon = MeshBeacon(
            senderHash: myHash,
            landmarks: landmarks,
            timestamp: Date().timeIntervalSince1970
        )
        guard let data = MeshEnvelope.wrap(beacon) else { return }
        do { try session.send(data, toPeers: session.connectedPeers, with: .reliable) } catch { print("[Mesh] Send failed: \(error.localizedDescription)") }
        print("[Mesh] Broadcast beacon with \(landmarks.count) landmarks to \(session.connectedPeers.count) peers")
    }

    // MARK: - Send/Receive

    private func broadcast(_ search: MeshSearch) {
        guard let data = MeshEnvelope.wrap(search),
              let session = session else { return }

        let peers = session.connectedPeers
        guard !peers.isEmpty else { return }

        do { try session.send(data, toPeers: peers, with: .reliable) } catch { print("[Mesh] Send failed: \(error.localizedDescription)") }
    }

    private func send(_ found: MeshFound, to peer: MCPeerID) {
        guard let data = MeshEnvelope.wrap(found),
              let session = session else { return }

        do { try session.send(data, toPeers: [peer], with: .reliable) } catch { print("[Mesh] Send failed: \(error.localizedDescription)") }
    }

    private func broadcastFound(_ found: MeshFound) {
        guard let data = MeshEnvelope.wrap(found),
              let session = session else { return }

        let peers = session.connectedPeers
        guard !peers.isEmpty else { return }

        do { try session.send(data, toPeers: peers, with: .reliable) } catch { print("[Mesh] Send failed: \(error.localizedDescription)") }
    }

    // MARK: - Handle Incoming

    private nonisolated func handleReceive(data: Data, from peer: MCPeerID) {
        guard let envelope = try? JSONDecoder().decode(MeshEnvelope.self, from: data) else { return }

        Task { @MainActor in
            switch envelope.type {
            case .search:
                if let search = envelope.unwrapSearch() {
                    await handleSearch(search, from: peer)
                }
            case .found:
                if let found = envelope.unwrapFound() {
                    await handleFound(found, from: peer)
                }
            case .beacon:
                if let beacon = envelope.unwrapBeacon() {
                    await handleBeacon(beacon, from: peer)
                }
            }
        }
    }

    private func handleSearch(_ search: MeshSearch, from peer: MCPeerID) async {
        // Dedup
        guard await dedup.shouldProcess(search.id) else { return }

        // Store routing: origin came from this peer
        routingTable[search.originID] = peer

        // Check if it's US they're looking for
        if search.queryHash == myHash {
            let landmarks = landmarkProvider?()
            let found = MeshFound.create(search: search, rssi: 0, landmarks: landmarks)
            send(found, to: peer)
            print("[Mesh] I'm the target! Responding to search \(search.id.prefix(8))")
            return
        }

        // Check if it matches one of our contacts
        if let contact = contactManager.lookup(search.queryHash) {
            // We know this person but they're not us — still useful info
            print("[Mesh] Contact \(contact.name) matches search, but they need to respond themselves")
        }

        // Rate limit
        guard checkRateLimit() else { return }

        // Forward with decremented TTL
        guard search.ttl > 0 else { return }

        var forwarded = search
        forwarded.ttl -= 1
        forwarded.hopCount += 1
        forwarded.path.append(myPeerID.displayName)

        // Forward to all peers EXCEPT the one that sent it
        guard let session = session else { return }
        let forwardPeers = session.connectedPeers.filter { $0 != peer }
        guard !forwardPeers.isEmpty else { return }

        if let data = MeshEnvelope.wrap(forwarded) {
            do { try session.send(data, toPeers: forwardPeers, with: .reliable) } catch { print("[Mesh] Send failed: \(error.localizedDescription)") }
            searchesRelayed += 1
            print("[Mesh] Relayed search for \(search.queryHash.prefix(8)) (TTL=\(forwarded.ttl), hops=\(forwarded.hopCount))")
        }
    }

    private func handleFound(_ found: MeshFound, from peer: MCPeerID) async {
        guard await dedup.shouldProcess(found.id) else { return }

        // Is this response for one of OUR searches?
        if myOriginIDs.contains(found.originID) {
            foundResponses += 1
            let contact = contactManager.lookup(found.queryHash)
            let name = contact?.name ?? "Unknown"
            print("[Mesh] FOUND response for our search: \(name) at \(found.hopCount) hops")
            delegate?.meshManager(self, didFindContact: name, hash: found.queryHash, hopCount: found.hopCount, rssiAtFind: found.rssiAtFind, landmarks: found.landmarks)
            return
        }

        // Route back toward originator
        if let nextHop = routingTable[found.originID] {
            var routed = found
            routed.hopCount += 1
            send(routed, to: nextHop)
            print("[Mesh] Routing FOUND back toward origin \(found.originID.prefix(8))")
        } else {
            // No route — flood with reduced TTL
            guard found.hopCount < 6 else { return }
            var flooded = found
            flooded.hopCount += 1
            broadcastFound(flooded)
            print("[Mesh] No route for FOUND, flooding (hops=\(flooded.hopCount))")
        }
    }

    private func handleBeacon(_ beacon: MeshBeacon, from peer: MCPeerID) async {
        guard !beacon.landmarks.isEmpty else { return }
        print("[Mesh] Received beacon from \(beacon.senderHash.prefix(8)) with \(beacon.landmarks.count) landmarks")
        delegate?.meshManager(self, didReceiveBeacon: beacon.senderHash, landmarks: beacon.landmarks)
    }

    private func checkRateLimit() -> Bool {
        let now = Date()
        if now.timeIntervalSince(forwardWindowStart) > 1.0 {
            forwardCount = 0
            forwardWindowStart = now
        }
        forwardCount += 1
        return forwardCount <= maxForwardsPerSecond
    }
}

// MARK: - MCSessionDelegate

extension MeshManager: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            connectedPeers = session.connectedPeers.count
            switch state {
            case .connected:
                print("[Mesh] Peer connected: \(peerID.displayName) (total: \(connectedPeers))")
            case .notConnected:
                print("[Mesh] Peer disconnected: \(peerID.displayName) (total: \(connectedPeers))")
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        handleReceive(data: data, from: peerID)
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MeshManager: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard let session = _session else { return }
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
        print("[Mesh] Found peer: \(peerID.displayName), inviting...")
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("[Mesh] Lost peer: \(peerID.displayName)")
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MeshManager: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept all invitations
        invitationHandler(true, _session)
        print("[Mesh] Accepted invitation from: \(peerID.displayName)")
    }
}
