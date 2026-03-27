# Marco

**Find your people when it matters most.**

Marco is an open-source iOS app that helps people find loved ones in disaster zones when cell service is down. It uses Bluetooth Low Energy to detect nearby contacts, mesh networking to extend range through strangers' devices, and passive BLE landmark triangulation for position accuracy — all with zero internet, zero servers, zero infrastructure.

## Demo

Two phones. Airplane mode. No WiFi. No cell service. They find each other.

## How It Works

### Layer 1: Identity
You enter your phone number. It's hashed locally (salted SHA256) and never stored or transmitted as plain text. Your contacts' numbers are hashed the same way for matching.

### Layer 2: Direct Detection (~30m)
Your phone broadcasts your hash via BLE and scans for nearby devices. When a hash matches someone in your contacts, Marco shows their name and estimated distance.

### Layer 3: Mesh Relay (~120m+)
Search queries hop through other Marco devices to find contacts beyond direct BLE range. A stranger's phone receives your query (an opaque hash), can't read it, and forwards it. When it reaches the target, a "found" response routes back through the chain. Each hop adds ~30m of range.

```
You → Stranger A → Stranger B → Your Family
 "looking for         relay         "that's me!"
  hash a83f1b"
```

### Layer 4: Passive Landmark Triangulation
Every BLE device in the environment (smart TVs, speakers, headphones, IoT devices) acts as a passive reference point. Two Marco devices that see the same landmarks can compute their relative positions using signal strength differences — indoor GPS without satellites.

## Features

- **Offline contact detection** — BLE-based, zero infrastructure
- **Mesh relay** — extend range through intermediate devices
- **Passive triangulation** — every BLE device is a landmark
- **Find My-style radar** — compass arrow, pulsing proximity rings, haptic feedback
- **Glass morphism UI** — dark theme with frosted glass cards
- **Kalman-filtered RSSI** — smoothed distance estimates
- **Privacy-preserving** — only salted SHA256 hashes are broadcast
- **Opt-in only** — nothing runs without explicit user action

## Architecture

```
Layer 4: Landmark Triangulation
  LandmarkTracker     — scans all BLE devices, classifies stable vs transient
  PositionEstimator   — trilaterates from shared landmarks
  KalmanFilter        — smooths noisy RSSI signals

Layer 3: Mesh Relay
  MeshManager         — MultipeerConnectivity session + SEARCH/FOUND protocol
  MeshMessage         — Codable message types with TTL + dedup
  DeduplicationCache  — prevents message loops

Layer 2: Direct Detection
  BLEScanner          — Core Bluetooth central, scans for Marco beacons
  BLEAdvertiser       — Core Bluetooth peripheral, broadcasts hash

Layer 1: Identity
  CryptoUtils         — SHA256 hashing with salt
  ContactHashManager  — loads contacts, computes hash lookup table
```

## Privacy

- **No data leaves your device** — all matching is local
- **No servers** — fully peer-to-peer
- **No location tracking** — only BLE proximity, no GPS
- **Hashed identifiers** — salted SHA256, truncated to 6 bytes
- **Mesh queries are opaque** — relay nodes see hashes, not names
- **Anonymous routing** — mesh origin IDs are random per session
- **Open source** — verify every claim by reading the code

## Getting Started

1. Clone:
   ```bash
   git clone https://github.com/zpphxd/Marco.git
   ```

2. Open in Xcode:
   ```bash
   open Marco.xcodeproj
   ```

3. Select your development team in **Signing & Capabilities**

4. Build and run on a **physical device** (BLE requires real hardware)

5. Enter your phone number, grant Bluetooth + Contacts permissions, tap the antenna

6. To test: install on a second device with a phone number that's in the first device's contacts

## Testing the Mesh

Need 3 phones:
- **Phone A**: searches for Phone C
- **Phone B**: runs Marco but has no contact relationship — acts as relay
- **Phone C**: has Phone A's number in contacts

Phone A should find Phone C *through* Phone B.

## Roadmap

- [x] Direct BLE contact detection
- [x] Find My-style radar with haptics
- [x] Mesh relay protocol (SEARCH/FOUND with TTL + dedup)
- [x] Passive BLE landmark tracking + Kalman filtering
- [x] Trilateration from shared landmarks
- [x] Glass morphism UI
- [ ] UWB direction finding (iPhone 11+)
- [ ] First responder mode (import missing persons list)
- [ ] Status broadcasting (OK / need help / injured)
- [ ] Background mode optimization
- [ ] Android cross-platform support
- [ ] Rotating keys (Find My-style privacy)

## How Landmark Triangulation Works

Every BLE device nearby is a reference point:

```
        Samsung TV (stable landmark)
       /            \
  3m  /              \ 12m
     /                \
   You    ~15m      Wife
     \                /
  8m  \              / 9m
       \            /
        Toothbrush (stable landmark)
```

Both phones see the same devices at different signal strengths. The difference in signal strength reveals relative distance. With 3+ shared landmarks, trilateration gives a position estimate.

Landmarks are classified automatically:
- **Stable** (low RSSI variance, static name, non-Apple manufacturer) → used for positioning
- **Transient** (high variance, rotating MAC) → ignored

## Contributing

This project exists to save lives. Contributions welcome.

Priority areas:
- BLE mesh networking / MultipeerConnectivity optimization
- Signal processing (better path-loss models, particle filters)
- UWB / NearbyInteraction integration
- Android BLE implementation
- UI/UX design
- Security audit of hashing scheme
- Real-world testing in disaster simulation scenarios

## License

MIT

## Acknowledgments

- [BerkananSDK](https://github.com/zssz/BerkananSDK) — BLE mesh patterns
- [BeaconIL](https://github.com/Vitaliy69/BeaconIL) — trilateration algorithms
- [SwiftGlass](https://github.com/1998code/SwiftGlass) — glass morphism inspiration
- TU Darmstadt [OpenDrop](https://github.com/seemoo-lab/opendrop) — AirDrop BLE research
- Apple's Core Bluetooth and MultipeerConnectivity frameworks
