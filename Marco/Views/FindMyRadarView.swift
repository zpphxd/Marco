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

// MARK: - Compass Needle Shape (classic dual-tone)

struct CompassNeedle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        let cy = rect.midY
        let needleWidth: CGFloat = rect.width * 0.14
        let needleLength: CGFloat = rect.height * 0.42

        // North half (pointed tip)
        path.move(to: CGPoint(x: cx, y: cy - needleLength))
        path.addLine(to: CGPoint(x: cx + needleWidth, y: cy))
        path.addLine(to: CGPoint(x: cx - needleWidth, y: cy))
        path.closeSubpath()

        return path
    }
}

struct CompassNeedleSouth: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        let cy = rect.midY
        let needleWidth: CGFloat = rect.width * 0.14
        let needleLength: CGFloat = rect.height * 0.32

        // South half (shorter, wider)
        path.move(to: CGPoint(x: cx, y: cy + needleLength))
        path.addLine(to: CGPoint(x: cx + needleWidth, y: cy))
        path.addLine(to: CGPoint(x: cx - needleWidth, y: cy))
        path.closeSubpath()

        return path
    }
}

// MARK: - Compass Dial

struct CompassDial: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.3), .white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
                .frame(width: size, height: size)

            // Degree tick marks
            ForEach(0..<72, id: \.self) { i in
                let isMajor = i % 18 == 0 // N, E, S, W
                let isMinor = i % 9 == 0  // NE, SE, SW, NW
                let length: CGFloat = isMajor ? 14 : isMinor ? 10 : 5
                let width: CGFloat = isMajor ? 2 : 1
                let opacity: Double = isMajor ? 0.7 : isMinor ? 0.4 : 0.15

                Rectangle()
                    .fill(Color.white.opacity(opacity))
                    .frame(width: width, height: length)
                    .offset(y: -size / 2 + length / 2 + 4)
                    .rotationEffect(.degrees(Double(i) * 5))
            }

            // Cardinal labels
            ForEach(Array(["N", "E", "S", "W"].enumerated()), id: \.offset) { index, label in
                Text(label)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(label == "N" ? .red.opacity(0.9) : .white.opacity(0.5))
                    .offset(y: -size / 2 + 30)
                    .rotationEffect(.degrees(Double(index) * 90))
            }

            // Intercardinal labels
            ForEach(Array(["NE", "SE", "SW", "NW"].enumerated()), id: \.offset) { index, label in
                Text(label)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
                    .offset(y: -size / 2 + 30)
                    .rotationEffect(.degrees(45 + Double(index) * 90))
            }

            // Inner decorative ring
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                .frame(width: size * 0.7, height: size * 0.7)

            // Innermost ring
            Circle()
                .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                .frame(width: size * 0.45, height: size * 0.45)
        }
    }
}

// MARK: - Pulsing Ring

struct PulsingRing: View {
    let color: Color
    let delay: Double
    let duration: Double

    @State private var scale: CGFloat = 0.4
    @State private var opacity: Double = 0.6

    var body: some View {
        Circle()
            .stroke(color, lineWidth: 1.5)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(
                    .easeOut(duration: duration)
                    .repeatForever(autoreverses: false)
                    .delay(delay)
                ) {
                    scale = 1.8
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
    @State private var dialRotation: Double = 0
    @StateObject private var headingManager = HeadingManager()
    @State private var targetBearing: Double = 0 // estimated bearing to target

    private let compassSize: CGFloat = 280

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
            // Background
            Color.black.ignoresSafeArea()

            // Subtle radial glow behind compass
            RadialGradient(
                colors: [proximityColor.opacity(0.08), .clear],
                center: .center,
                startRadius: 50,
                endRadius: 250
            )
            .offset(y: -40)
            .ignoresSafeArea()

            VStack(spacing: 0) {
                contactHeader
                    .padding(.top, 16)

                Spacer()

                // Compass
                compassView
                    .frame(width: compassSize + 40, height: compassSize + 40)

                directionLabel
                    .padding(.top, 16)

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
            headingManager.start()
            startHaptics()
            updateArrow()
        }
        .onDisappear {
            headingManager.stop()
            hapticTimer?.invalidate()
        }
        .onChange(of: contact.rssi) { _, _ in
            updateArrow()
            updateHapticRate()
        }
        .onChange(of: headingManager.heading) { _, newHeading in
            withAnimation(.easeOut(duration: 0.3)) {
                // Dial shows real compass heading (rotate opposite so N stays "up" relative to world)
                dialRotation = -newHeading
            }
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
                HStack(spacing: 4) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.caption2)
                    Text("Via mesh (\(hopCount) hop\(hopCount == 1 ? "" : "s"))")
                        .font(.caption)
                }
                .foregroundColor(.blue)
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Compass View

    private var compassView: some View {
        ZStack {
            // Glass compass bezel
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: compassSize + 20, height: compassSize + 20)
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.4), .white.opacity(0.05), .white.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 12)

            // Inner dark face
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.12), Color(white: 0.06)],
                        center: .center,
                        startRadius: 0,
                        endRadius: compassSize / 2
                    )
                )
                .frame(width: compassSize, height: compassSize)

            // Compass dial (tick marks + labels) — tracks real compass heading
            CompassDial(size: compassSize)
                .rotationEffect(.degrees(dialRotation))

            // Sonar pulses from center
            ForEach(0..<3, id: \.self) { i in
                PulsingRing(
                    color: proximityColor,
                    delay: Double(i) * (pulseSpeed / 3),
                    duration: pulseSpeed
                )
                .frame(width: compassSize * 0.35, height: compassSize * 0.35)
            }

            // Compass needle — north half (colored by proximity)
            CompassNeedle()
                .fill(
                    LinearGradient(
                        colors: [proximityColor, proximityColor.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .frame(width: compassSize * 0.85, height: compassSize * 0.85)
                .shadow(color: proximityColor.opacity(0.5), radius: 10)
                .rotationEffect(.degrees(arrowRotation))

            // Compass needle — south half (dark)
            CompassNeedleSouth()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.15), Color.white.opacity(0.05)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                )
                .frame(width: compassSize * 0.85, height: compassSize * 0.85)
                .rotationEffect(.degrees(arrowRotation))

            // Center pivot
            ZStack {
                Circle()
                    .fill(Color(white: 0.2))
                    .frame(width: 20, height: 20)

                Circle()
                    .fill(proximityColor)
                    .frame(width: 12, height: 12)
                    .shadow(color: proximityColor, radius: 6)
            }

            // Distance overlay on compass face
            Text(distanceText)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .offset(y: compassSize * 0.28)
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
        // Update target bearing estimate based on signal trend
        switch contact.trend {
        case .approaching:
            // Signal getting stronger — we're heading toward them
            // Lock the bearing to current heading (they're "ahead")
            targetBearing = headingManager.heading
        case .receding:
            // Signal getting weaker — they're behind us
            // Bearing is opposite of current heading
            targetBearing = headingManager.heading + 180
        case .stable:
            // Keep last known bearing, add slight drift
            targetBearing += Double.random(in: -5...5)
        }

        // Needle points toward target, adjusted for current heading
        // Since the dial already rotates with heading, the needle shows
        // the relative direction from our current facing
        let relativeAngle = targetBearing - headingManager.heading

        withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
            arrowRotation = relativeAngle
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
