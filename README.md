# Marco

**Find your people when it matters most.**

Marco is an open-source iOS app that helps people find loved ones in disaster zones when cell service is down. It uses Bluetooth Low Energy (BLE) to detect nearby contacts — no internet, no servers, no infrastructure required.

## How It Works

1. You enter your phone number (hashed locally, never stored or transmitted as plain text)
2. Marco loads your contacts and creates privacy-preserving hashes of their phone numbers
3. Your phone broadcasts your hash via BLE and scans for nearby devices
4. When a nearby device's hash matches someone in your contacts, Marco alerts you with their name and estimated distance
5. A Find My-style radar screen guides you toward them with real-time distance feedback and haptic pulses

**Both devices need Marco installed.** No internet connection is needed after initial app install.

## The Problem

When disasters strike — hurricanes, earthquakes, wildfires — cell towers go down. The first question everyone asks is: *"Where is my family?"*

Existing solutions (Find My, phone calls, texts) all require infrastructure. Marco works with nothing but the Bluetooth radio already in every phone.

## Demo

Two phones. Airplane mode. No WiFi. No cell service. They find each other.

## Features

- **Offline contact detection** — BLE-based, zero infrastructure needed
- **Privacy-preserving** — only salted SHA256 hashes are broadcast, never names or numbers
- **Distance estimation** — RSSI-based distance with trend detection (getting closer/farther)
- **Find My-style radar** — pulsing proximity visualization with haptic feedback
- **Mutual detection** — both devices see each other simultaneously
- **Opt-in only** — user explicitly starts scanning, nothing runs in the background without consent

## Architecture

```
┌─────────────────────────────┐
│         SwiftUI App         │
│  ┌────────┐ ┌────────────┐  │
│  │ Setup  │ │  Radar UI  │  │
│  └───┬────┘ └─────┬──────┘  │
│      └──────┬─────┘         │
│      ┌──────▼──────┐        │
│      │  ViewModel  │        │
│      └──┬───────┬──┘        │
│    ┌────▼──┐ ┌──▼────────┐  │
│    │  BLE  │ │ Contacts  │  │
│    │Scanner│ │HashManager │  │
│    │Advert.│ └───────────┘  │
│    └───────┘                │
└─────────────────────────────┘
```

### Key Components

| File | Purpose |
|------|---------|
| `BLEScanner.swift` | Core Bluetooth central — scans for nearby Marco devices |
| `BLEAdvertiser.swift` | Core Bluetooth peripheral — broadcasts your hashed identity |
| `ContactHashManager.swift` | Loads contacts, computes hashes, provides lookup |
| `CryptoUtils.swift` | SHA256 hashing with salt, phone number normalization |
| `RadarViewModel.swift` | Coordinates scanning, matching, and state |
| `FindMyRadarView.swift` | Find My-style proximity radar with haptics |

## Privacy

Marco is designed with privacy as a core constraint:

- **No data leaves your device** — all matching happens locally
- **No servers** — peer-to-peer BLE only
- **No location tracking** — only BLE proximity (near/far), no GPS coordinates
- **Hashed identifiers** — your phone number is salted and hashed before broadcast
- **Opt-in** — you manually start scanning; nothing runs without your action
- **Open source** — verify every claim by reading the code

## Requirements

- iOS 17.0+ / macOS 14.0+
- Xcode 15+
- Bluetooth LE capable device
- Physical device required for BLE testing (simulators don't have Bluetooth)

## Getting Started

1. Clone the repo:
   ```bash
   git clone https://github.com/zpphxd/Marco.git
   ```

2. Open in Xcode:
   ```bash
   cd Marco
   open Marco.xcodeproj
   ```

3. Select your development team in **Signing & Capabilities**

4. Build and run on a physical device (Cmd+R)

5. On first launch:
   - Enter your phone number
   - Grant Bluetooth and Contacts permissions
   - Tap the antenna to start scanning

6. To test: install on a second device with a phone number that's in the first device's contacts

## Roadmap

- [ ] **Mesh relay** — relay hash queries through intermediate devices to extend range beyond BLE (~30m → unlimited with enough nodes)
- [ ] **Triangulation** — multiple observers computing position from RSSI intersection
- [ ] **First responder mode** — import a list of missing people, scan for them as you move through a disaster zone
- [ ] **UWB direction finding** — precise pointing direction on iPhone 11+ using Ultra-Wideband
- [ ] **Status broadcasting** — broadcast your status (OK / need help / injured / can help)
- [ ] **Background mode** — continue scanning when the app is backgrounded
- [ ] **Rotating keys** — Find My-style key rotation for enhanced privacy
- [ ] **Android support** — same BLE protocol, cross-platform detection

## How Mesh Relay Works (Planned)

```
You ←BLE→ Stranger A ←BLE→ Stranger B ←BLE→ Your Family
 30m          30m           30m
         Total reach: ~90m+
```

Intermediate devices relay hash queries without knowing who you're looking for. They see hashes, not names. Your query hops from device to device until it finds a match, then the "found" signal hops back.

## Contributing

This project exists to save lives. Contributions welcome.

1. Fork the repo
2. Create a feature branch
3. Submit a PR

Areas where help is most needed:
- BLE mesh networking / MultipeerConnectivity
- Signal processing (Kalman filtering for RSSI smoothing)
- UWB/NearbyInteraction integration
- Android BLE implementation
- UI/UX design
- Security review of the hashing scheme

## License

MIT — use it however you want. If it helps someone find their family, that's all that matters.

## Acknowledgments

- [OpenDrop](https://github.com/seemoo-lab/opendrop) — TU Darmstadt's AirDrop research that informed the BLE analysis
- Apple's Core Bluetooth and MultipeerConnectivity frameworks
- The Meshtastic and Bridgefy projects for proving mesh networking works on consumer devices
