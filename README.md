# Marco

**Find your people when it matters most.**

Marco is an open-source iOS app that finds people you know nearby using only Bluetooth — no internet, no cell service, no servers, no infrastructure. A compass-style radar guides you toward them in real time with haptic feedback, and mesh networking extends your range through other devices.

## The Problem

You're separated from your family. Your phone has no signal. Find My doesn't work. You can't call, text, or search. All you know is they're somewhere nearby.

This happens more often than you think:

### Disaster Zones
Hurricanes, earthquakes, wildfires, floods — cell towers go down first. After the 2023 Turkey earthquake, families spent days walking between hospitals and morgues searching for each other. After Hurricane Maria, Puerto Rico had no cell service for months. Marco works with nothing but the Bluetooth radio already in every phone.

### Concerts & Festivals
50,000 people. No cell service because the towers are overloaded. Your group got separated. Marco finds them through the crowd — every other phone running Marco acts as a relay, extending your range across the entire venue.

### Airports & Theme Parks
Lost your kid in a crowd? Cell service is spotty inside buildings. GPS doesn't work indoors. Marco uses nearby Bluetooth devices (every smart TV, speaker, kiosk) as indoor landmarks to triangulate position — no GPS needed.

### Protests & Large Gatherings
When authorities restrict cell service, Marco's mesh relay keeps working. Messages hop phone-to-phone. Nobody can shut it down because there's no server to shut down.

### Rural & Remote Areas
Hiking, camping, backcountry — no cell towers. Marco works between any two phones within Bluetooth range (~30m direct, further with mesh relay through other hikers).

### International Travel
No local SIM, roaming disabled, WiFi-only phone. Marco doesn't care — Bluetooth works everywhere, in every country, on every carrier.

## How It Works

### Layer 1: Identity
You enter your phone number. It's hashed locally (salted SHA256, truncated to 6 bytes) and never stored or transmitted as plain text. Marco hashes all your contacts' numbers the same way and keeps a lookup table on-device.

### Layer 2: Direct Detection (~30m range)
Your phone broadcasts your hash via Bluetooth Low Energy and scans for nearby devices. When a detected hash matches someone in your contacts, Marco shows their name, estimated distance, and a compass pointing toward them.

### Layer 3: Mesh Relay (120m+ range)
Your search query hops through other Marco devices. A stranger's phone receives your query (an opaque hash it can't read), forwards it to everyone nearby, and so on. When it reaches the person you're looking for, a "found" response routes back through the chain. Each hop adds ~30m of range. In a crowd of hundreds, your effective range covers the entire area.

```
You → Stranger A → Stranger B → Your Family
 "looking for         relay          "that's me!"
  hash a83f1b"
You ← Stranger A ← Stranger B ← "FOUND"
 compass now
 points toward them
```

Strangers see nothing but opaque hashes. They can't tell who's searching or who was found.

### Layer 4: Passive Landmark Triangulation
Every Bluetooth device in the environment — smart TVs, speakers, headphones, watches, IoT sensors — acts as a reference point. Both phones see the same devices at different signal strengths. The difference reveals relative distance and direction. More landmarks = more accuracy. No app needed on those devices.

```
        Samsung TV (landmark)
       /            \
  3m  /              \ 12m
     /                \
   You    ~15m      Family
     \                /
  8m  \              / 9m
       \            /
        Speaker (landmark)
```

### Compass Radar
When you tap a detected contact, Marco opens a full-screen compass:

- **Real compass heading** — synced to the device magnetometer, N/E/S/W rotate with the real world
- **Direction needle** — continuously samples signal strength at different headings, weighted average points toward the strongest signal direction
- **Pulsing sonar rings** — pulse faster as you get closer
- **Haptic feedback** — phone buzzes faster the closer you get (heavy when very close, light when far)
- **Distance estimate** — computed from signal strength with Kalman filtering for smoothness
- **Glass morphism UI** — frosted glass cards with gradient borders, dark background

**How to use it:**
1. Open the radar on a detected contact
2. Turn slowly in place — "Turn slowly to calibrate..."
3. The needle locks onto the direction where signal is strongest
4. Walk that way — "Getting Closer — Keep Going"
5. If signal drops — "Wrong Way — Follow the Arrow"
6. Haptics buzz faster as you approach
7. The distance card counts down in real time

## Features

- **Fully offline** — no internet, no servers, no infrastructure, no accounts
- **Privacy-preserving** — only hashed identifiers broadcast, never names or numbers
- **Mesh networking** — extend range through intermediate devices
- **Passive triangulation** — every BLE device is a landmark
- **Real compass** — synced to device magnetometer
- **Haptic guidance** — feel your way to the target without looking at the screen
- **Kalman-filtered RSSI** — smooth, stable distance estimates
- **Glass morphism UI** — dark theme with frosted glass cards
- **Landmark classification** — automatically identifies stable vs transient BLE devices
- **Weighted bearing estimation** — samples signal at multiple headings for accurate direction
- **Background BLE** — continues scanning when backgrounded (with permission)
- **Open source** — verify every privacy claim by reading the code

## Architecture

```
Layer 4: Landmark Triangulation
  LandmarkTracker      — scans all BLE, classifies stable vs transient
  PositionEstimator    — trilaterates from shared landmarks
  KalmanFilter         — smooths noisy RSSI signals

Layer 3: Mesh Relay
  MeshManager          — MultipeerConnectivity + SEARCH/FOUND protocol
  MeshMessage          — message types with TTL, dedup, source routing
  DeduplicationCache   — prevents message loops and storms

Layer 2: Direct Detection
  BLEScanner           — Core Bluetooth central, scans for Marco beacons
  BLEAdvertiser        — Core Bluetooth peripheral, broadcasts hash

Layer 1: Identity
  CryptoUtils          — SHA256 hashing with salt + phone number normalization
  ContactHashManager   — loads contacts, computes hash lookup table
```

## Privacy

- **No data leaves your device** — all matching happens locally
- **No servers** — fully peer-to-peer
- **No accounts** — no sign-up, no login, no tracking
- **No location sharing** — only Bluetooth proximity, never GPS coordinates
- **Hashed identifiers** — salted SHA256, truncated to 6 bytes
- **Mesh queries are opaque** — relay nodes see hashes, not names or numbers
- **Anonymous routing** — mesh origin IDs are random per session
- **No persistent tracking** — hashes are session-based, no long-term identifier
- **Open source** — every line of code is auditable

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

6. To test: install on a second device with a phone number in the first device's contacts

## Testing

### Two-Phone Test (Direct BLE)
- Install on both phones
- Both enter their own phone number
- Each has the other's number in contacts
- Put both in airplane mode
- Start scanning — they should detect each other within seconds
- Tap the detected contact to open the compass radar
- Walk around — compass guides you toward each other

### Three-Phone Test (Mesh Relay)
- Phone A searches for Phone C
- Phone B runs Marco but has no contact relationship — acts as relay
- Phone C has Phone A's number in contacts
- Turn WiFi ON (but not connected to any network) for mesh relay
- Phone A should find Phone C through Phone B

### Demo Mode
- Tap the play button (top left) on the main screen
- Shows a simulated contact with animated compass, distance, and haptics
- Great for showing people how it works without a second phone

## Roadmap

- [x] Direct BLE contact detection
- [x] Compass radar with real magnetometer heading
- [x] Weighted bearing estimation from heading-RSSI samples
- [x] Mesh relay protocol (SEARCH/FOUND with TTL + dedup)
- [x] Passive BLE landmark tracking + Kalman filtering
- [x] Trilateration from shared landmarks
- [x] Glass morphism UI with expandable detail panel
- [x] Haptic feedback scaled to proximity
- [x] Demo mode
- [ ] UWB direction finding (iPhone 11+ — centimeter accuracy)
- [ ] First responder mode (import list of missing people)
- [ ] Status broadcasting (OK / need help / injured / can help)
- [ ] Background mode optimization
- [ ] Android cross-platform support
- [ ] Rotating keys (Find My-style privacy enhancement)
- [ ] Voice clip relay over mesh
- [ ] SOS beacon with GPS coordinates

## Contributing

This project exists to help people find each other. Contributions welcome.

Priority areas:
- BLE mesh networking optimization
- Signal processing (particle filters, better path-loss models)
- UWB / NearbyInteraction integration for precise direction
- Android BLE implementation (cross-platform detection)
- UI/UX design and accessibility
- Security audit of hashing scheme
- Real-world testing in crowd scenarios
- Localization / internationalization

## License

MIT — use it however you want. If it helps someone find their family, that's all that matters.

## Acknowledgments

- [BerkananSDK](https://github.com/zssz/BerkananSDK) — BLE mesh patterns
- [BeaconIL](https://github.com/Vitaliy69/BeaconIL) — trilateration algorithms
- [SwiftGlass](https://github.com/1998code/SwiftGlass) — glass morphism inspiration
- TU Darmstadt [OpenDrop](https://github.com/seemoo-lab/opendrop) — AirDrop BLE research
- Apple Core Bluetooth and MultipeerConnectivity frameworks
