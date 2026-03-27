import SwiftUI
#if os(iOS)
import UIKit
#endif

struct FindMyRadarView: View {
    let contact: NearbyContact
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.8
    @State private var ringPhase: Double = 0
    @State private var lastHapticRSSI: Int = -100
    @State private var hapticTimer: Timer?

    // Smoothed signal (simple exponential moving average)
    @State private var smoothedRSSI: Double = -80

    private var signalStrength: Double {
        // Normalize RSSI to 0.0 - 1.0 range
        // -30 = strongest realistic, -100 = weakest
        let clamped = min(max(Double(contact.rssi), -100), -30)
        return (clamped + 100) / 70
    }

    private var distanceMeters: Double {
        // Rough RSSI to distance using log-distance path loss model
        // Reference: RSSI = -50 at 1 meter (typical BLE)
        let txPower: Double = -50
        let n: Double = 2.5 // path loss exponent (2 = free space, 3-4 = indoors)
        let ratio = (txPower - Double(contact.rssi)) / (10 * n)
        return pow(10, ratio)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Contact info header
            VStack(spacing: 4) {
                Text(contact.name)
                    .font(.title2.weight(.bold))

                if let phone = contact.phoneNumber {
                    Text(phone)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 20)

            Spacer()

            // Radar visualization
            ZStack {
                // Outer rings (pulse outward)
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(ringColor.opacity(0.15 - Double(i) * 0.04), lineWidth: 1.5)
                        .frame(width: ringSize(for: i), height: ringSize(for: i))
                }

                // Pulsing proximity circle
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                proximityColor.opacity(0.6),
                                proximityColor.opacity(0.2),
                                proximityColor.opacity(0.0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: proximityRadius
                        )
                    )
                    .frame(width: proximityRadius * 2, height: proximityRadius * 2)
                    .scaleEffect(pulseScale)
                    .opacity(pulseOpacity)

                // Inner solid circle
                Circle()
                    .fill(proximityColor)
                    .frame(width: innerCircleSize, height: innerCircleSize)
                    .shadow(color: proximityColor.opacity(0.5), radius: 20)

                // Arrow indicator
                VStack(spacing: 4) {
                    Image(systemName: trendIcon)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)

                    Text(distanceText)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 350)

            Spacer()

            // Bottom info
            VStack(spacing: 12) {
                // Direction feedback
                Text(directionText)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(proximityColor)
                    .animation(.easeInOut(duration: 0.3), value: contact.trend)

                // Signal details
                HStack(spacing: 24) {
                    VStack {
                        Text("\(contact.rssi)")
                            .font(.title3.weight(.bold).monospacedDigit())
                        Text("RSSI")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    VStack {
                        Text(String(format: "%.1fm", distanceMeters))
                            .font(.title3.weight(.bold).monospacedDigit())
                        Text("Est. Distance")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    VStack {
                        Text(contact.distance.rawValue.components(separatedBy: " ").first ?? "")
                            .font(.title3.weight(.bold))
                        Text("Range")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 8)

                // Signal strength bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [.red, .orange, .yellow, .green],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * signalStrength, height: 8)
                            .animation(.easeInOut(duration: 0.3), value: signalStrength)
                    }
                }
                .frame(height: 8)
                .padding(.horizontal, 40)
            }
            .padding(.bottom, 30)
        }
        .onAppear {
            startPulseAnimation()
            startHaptics()
            smoothedRSSI = Double(contact.rssi)
        }
        .onDisappear {
            hapticTimer?.invalidate()
        }
        .onChange(of: contact.rssi) { _, newValue in
            // Exponential moving average
            smoothedRSSI = smoothedRSSI * 0.7 + Double(newValue) * 0.3
            updateHapticRate()
        }
    }

    // MARK: - Computed Properties

    private var proximityColor: Color {
        switch signalStrength {
        case 0.7...: return .green
        case 0.5..<0.7: return .yellow
        case 0.3..<0.5: return .orange
        default: return .red
        }
    }

    private var ringColor: Color {
        proximityColor
    }

    private var proximityRadius: CGFloat {
        40 + CGFloat(signalStrength) * 80
    }

    private var innerCircleSize: CGFloat {
        30 + CGFloat(signalStrength) * 40
    }

    private func ringSize(for index: Int) -> CGFloat {
        let base = proximityRadius * 2 + 40
        return base + CGFloat(index) * 50
    }

    private var distanceText: String {
        if distanceMeters < 1 {
            return "< 1m"
        } else if distanceMeters < 10 {
            return String(format: "%.1fm", distanceMeters)
        } else {
            return String(format: "%.0fm", distanceMeters)
        }
    }

    private var directionText: String {
        switch contact.trend {
        case .approaching: return "Getting Closer"
        case .receding: return "Moving Away"
        case .stable: return "Hold Still..."
        }
    }

    private var trendIcon: String {
        switch contact.trend {
        case .approaching: return "arrow.down"
        case .receding: return "arrow.up"
        case .stable: return "circle.fill"
        }
    }

    // MARK: - Animations

    private func startPulseAnimation() {
        withAnimation(
            .easeInOut(duration: 1.2)
            .repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.15
            pulseOpacity = 0.4
        }
    }

    // MARK: - Haptics

    private func startHaptics() {
        #if os(iOS)
        updateHapticRate()
        #endif
    }

    private func updateHapticRate() {
        #if os(iOS)
        hapticTimer?.invalidate()

        // Haptic interval: closer = faster buzzing
        // Signal strength 0.0-1.0 maps to interval 2.0s - 0.1s
        let interval = max(0.1, 2.0 - (signalStrength * 1.9))

        hapticTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            let generator = UIImpactFeedbackGenerator(style: signalStrength > 0.6 ? .heavy : .medium)
            generator.impactOccurred(intensity: CGFloat(min(1.0, signalStrength + 0.3)))
        }
        #endif
    }
}
