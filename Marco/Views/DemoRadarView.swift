import SwiftUI

struct DemoRadarView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var demoViewModel = RadarViewModel()
    @State private var simulatedRSSI: Int = -85
    @State private var rssiHistory: [Int] = [-85]
    @State private var timer: Timer?
    @State private var direction: Int = 1 // 1 = getting closer, -1 = getting farther

    private var demoContact: NearbyContact {
        NearbyContact(
            id: "demo-contact",
            name: "Emily Powers",
            phoneNumber: "+1 (555) 867-5309",
            rssi: simulatedRSSI,
            distance: DistanceEstimate.from(rssi: simulatedRSSI),
            firstSeen: Date().addingTimeInterval(-30),
            lastSeen: Date(),
            rssiHistory: rssiHistory
        )
    }

    var body: some View {
        ZStack {
            FindMyRadarView(
                contactID: nil,
                viewModel: demoViewModel,
                contactOverride: demoContact,
                sharedLandmarks: 7,
                hopCount: 0,
                meshDistance: nil
            )

            // Close button
            VStack {
                HStack {
                    Button {
                        timer?.invalidate()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.leading, 20)
                    .padding(.top, 16)

                    Spacer()

                    Text("DEMO")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.yellow)
                        .clipShape(Capsule())
                        .padding(.trailing, 20)
                        .padding(.top, 16)
                }
                Spacer()
            }
        }
        .onAppear {
            startSimulation()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private func startSimulation() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            let noise = Int.random(in: -2...2)
            // Stronger steps so trend crosses the 8 dBm threshold clearly
            simulatedRSSI += (direction * 4) + noise

            // Bounce between close and far
            if simulatedRSSI > -35 {
                direction = -1
            } else if simulatedRSSI < -90 {
                direction = 1
            }

            simulatedRSSI = min(-30, max(-95, simulatedRSSI))

            rssiHistory.append(simulatedRSSI)
            if rssiHistory.count > 20 {
                rssiHistory.removeFirst()
            }
        }
    }
}
