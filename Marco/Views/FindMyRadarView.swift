import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Glass Effect Modifier

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.5), .white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}

// MARK: - Compass Arrow Shape

struct CompassArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: w * 0.5, y: 0))
        path.addLine(to: CGPoint(x: w * 0.65, y: h * 0.35))
        path.addLine(to: CGPoint(x: w * 0.55, y: h * 0.3))
        path.addLine(to: CGPoint(x: w * 0.55, y: h))
        path.addLine(to: CGPoint(x: w * 0.45, y: h))
        path.addLine(to: CGPoint(x: w * 0.45, y: h * 0.3))
        path.addLine(to: CGPoint(x: w * 0.35, y: h * 0.35))
        path.closeSubpath()

        return path
    }
}

// MARK: - Pulsing Ring

struct PulsingRing: View {
    let color: Color
    let delay: Double
    let duration: Double

    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.6

    var body: some View {
        Circle()
            .stroke(color, lineWidth: 2)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(
                    .easeOut(duration: duration)
                    .repeatForever(autoreverses: false)
                    .delay(delay)
                ) {
                    scale = 2.2
                    opacity = 0
                }
            }
    }
}

// MARK: - Main Radar View

struct FindMyRadarView: View {
    let contact: NearbyContact
    var sharedLandmarks: Int = 0
    var hopCount: Int = 0
    var meshDistance: Double? = nil

    @State private var arrowRotation: Double = 0
    @State private var hapticTimer: Timer?

    private var signalStrength: Double {
        let clamped = min(max(Double(contact.rssi), -100), -30)
        return (clamped + 100) / 70
    }

    private var distanceMeters: Double {
        if let mesh = meshDistance { return mesh }
        let n: Double = 2.5
        let ratio = (-50.0 - Double(contact.rssi)) / (10 * n)
        return pow(10, ratio)
    }

    private var proximityColor: Color {
        switch signalStrength {
        case 0.7...: return .green
        case 0.5..<0.7: return .yellow
        case 0.3..<0.5: return .orange
        default: return .red
        }
    }

    private var pulseSpeed: Double {
        max(0.4, 2.0 - signalStrength * 1.6)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(white: 0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                contactHeader
                    .padding(.top, 16)

                Spacer()

                compassRadar
                    .frame(height: 300)

                directionLabel
                    .padding(.top, 20)

                Spacer()

                distanceCard
                    .padding(.horizontal, 20)

                statsRow
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
            }
        }
        .onAppear {
            startHaptics()
            updateArrow()
        }
        .onDisappear {
            hapticTimer?.invalidate()
        }
        .onChange(of: contact.rssi) { _, _ in
            updateArrow()
            updateHapticRate()
        }
    }

    // MARK: - Contact Header

    private var contactHeader: some View {
        VStack(spacing: 4) {
            Text(contact.name)
                .font(.title2.weight(.bold))
                .foregroundColor(.white)

            if let phone = contact.phoneNumber {
                Text(phone)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            }

            if hopCount > 0 {
                Text("Found via mesh (\(hopCount) hop\(hopCount == 1 ? "" : "s"))")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Compass Radar

    private var compassRadar: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                PulsingRing(
                    color: proximityColor,
                    delay: Double(i) * 0.5,
                    duration: pulseSpeed
                )
                .frame(width: 140, height: 140)
            }

            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                    .frame(
                        width: CGFloat(100 + i * 60),
                        height: CGFloat(100 + i * 60)
                    )
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [proximityColor.opacity(0.3), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 80
                    )
                )
                .frame(width: 160, height: 160)

            CompassArrow()
                .fill(
                    LinearGradient(
                        colors: [proximityColor, proximityColor.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 40, height: 120)
                .shadow(color: proximityColor.opacity(0.6), radius: 12)
                .rotationEffect(.degrees(arrowRotation))

            Circle()
                .fill(proximityColor)
                .frame(width: 16, height: 16)
                .shadow(color: proximityColor, radius: 8)
        }
    }

    // MARK: - Direction Label

    private var directionLabel: some View {
        Text(directionText)
            .font(.title3.weight(.semibold))
            .foregroundColor(proximityColor)
            .animation(.easeInOut(duration: 0.3), value: contact.trend.rawValue)
    }

    private var directionText: String {
        switch contact.trend {
        case .approaching: return "Getting Closer"
        case .receding: return "Moving Away"
        case .stable: return "Hold Still..."
        }
    }

    // MARK: - Distance Card

    private var distanceCard: some View {
        VStack(spacing: 12) {
            Text(distanceText)
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.red, .orange, .yellow, .green],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geo.size.width * signalStrength), height: 6)
                        .animation(.easeInOut(duration: 0.3), value: signalStrength)
                }
            }
            .frame(height: 6)
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 20)
        .glassCard()
    }

    private var distanceText: String {
        if distanceMeters < 1 { return "< 1m" }
        else if distanceMeters < 10 { return String(format: "%.1fm", distanceMeters) }
        else { return String(format: "%.0fm", distanceMeters) }
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 8) {
            statPill(icon: "wave.3.right", value: "\(contact.rssi)", label: "RSSI")
            statPill(icon: "ruler", value: String(format: "%.1f", distanceMeters), label: "Meters")
            statPill(icon: "mappin.and.ellipse", value: "\(sharedLandmarks)", label: "Landmarks")
            statPill(icon: "arrow.triangle.swap", value: "\(hopCount)", label: "Hops")
        }
    }

    private func statPill(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
            Text(value)
                .font(.system(.callout, design: .monospaced).weight(.bold))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 14)
    }

    // MARK: - Arrow Animation

    private func updateArrow() {
        let newRotation: Double
        switch contact.trend {
        case .approaching: newRotation = 0
        case .receding: newRotation = 180
        case .stable: newRotation = arrowRotation + 15
        }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            arrowRotation = newRotation
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
        let interval = max(0.15, 2.0 - signalStrength * 1.85)
        hapticTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            let style: UIImpactFeedbackGenerator.FeedbackStyle =
                signalStrength > 0.7 ? .heavy : signalStrength > 0.4 ? .medium : .light
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.impactOccurred(intensity: min(1.0, CGFloat(signalStrength) + 0.2))
        }
        #endif
    }
}
