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

// MARK: - Signal Ring (replaces fake compass)

struct SignalRing: View {
    let signalStrength: Double // 0.0 to 1.0
    let color: Color

    @State private var animate = false

    var body: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: 12)

            // Signal arc
            Circle()
                .trim(from: 0, to: signalStrength)
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.3), color],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(-90 + 360 * signalStrength)
                    ),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: signalStrength)
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
    let contactID: String?
    @ObservedObject var viewModel: RadarViewModel
    var contactOverride: NearbyContact? = nil
    var sharedLandmarks: Int = 0
    var hopCount: Int = 0
    var meshDistance: Double? = nil

    private var contact: NearbyContact {
        if let id = contactID,
           let live = viewModel.nearbyContacts.first(where: { $0.id == id }) {
            return live
        }
        return contactOverride ?? NearbyContact(
            id: "missing", name: "Lost Signal", phoneNumber: nil,
            rssi: -100, distance: .unknown, firstSeen: Date(),
            lastSeen: Date(), rssiHistory: []
        )
    }

    @State private var hapticTimer: Timer?
    @State private var logCounter = 0

    private let radarSize: CGFloat = 260

    private var signalStrength: Double {
        let clamped = min(max(Double(contact.rssi), -100), -30)
        return (clamped + 100) / 70
    }

    private var distanceMeters: Double {
        if let mesh = meshDistance { return mesh }
        let n: Double = 2.5
        let ratio = (-59.0 - Double(contact.rssi)) / (10 * n)
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
            Color.black.ignoresSafeArea()

            // Subtle radial glow
            RadialGradient(
                colors: [proximityColor.opacity(0.06), .clear],
                center: .center,
                startRadius: 50,
                endRadius: 300
            )
            .offset(y: -40)
            .ignoresSafeArea()

            VStack(spacing: 0) {
                contactHeader
                    .padding(.top, 16)

                Spacer()

                // Signal radar (honest — shows strength, not direction)
                signalRadar
                    .frame(width: radarSize + 40, height: radarSize + 40)

                // Guidance text
                guidanceLabel
                    .padding(.top, 16)

                Spacer()

                bottomPanel
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
            }
        }
        .onAppear {
            startHaptics()
        }
        .onDisappear {
            hapticTimer?.invalidate()
        }
        .onChange(of: contact.rssi) { _, _ in
            updateHapticRate()
            logUpdate()
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

    // MARK: - Signal Radar

    private var signalRadar: some View {
        ZStack {
            // Glass bezel
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: radarSize + 20, height: radarSize + 20)
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

            // Dark face
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.12), Color(white: 0.06)],
                        center: .center,
                        startRadius: 0,
                        endRadius: radarSize / 2
                    )
                )
                .frame(width: radarSize, height: radarSize)

            // Distance rings (concentric labels)
            ForEach([0.3, 0.55, 0.8], id: \.self) { scale in
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                    .frame(width: radarSize * scale, height: radarSize * scale)
            }

            // Sonar pulses
            ForEach(0..<3, id: \.self) { i in
                PulsingRing(
                    color: proximityColor,
                    delay: Double(i) * (pulseSpeed / 3),
                    duration: pulseSpeed
                )
                .frame(width: radarSize * 0.3, height: radarSize * 0.3)
            }

            // Signal strength ring
            SignalRing(signalStrength: signalStrength, color: proximityColor)
                .frame(width: radarSize * 0.7, height: radarSize * 0.7)

            // Center — signal percentage
            VStack(spacing: 4) {
                Text("\(Int(signalStrength * 100))%")
                    .font(.system(size: 42, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                Text("SIGNAL")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                    .tracking(2)
            }

            // Distance on compass face
            Text(distanceText)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .offset(y: radarSize * 0.32)
        }
    }

    // MARK: - Guidance Label

    private var guidanceLabel: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: trendIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(trendColor)

                Text(guidanceText)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(trendColor)
            }
            .animation(.easeInOut(duration: 0.3), value: contact.trend.rawValue)

            Text("Walk around — signal strength guides you")
                .font(.caption)
                .foregroundColor(.white.opacity(0.3))
        }
    }

    private var guidanceText: String {
        switch contact.trend {
        case .approaching: return "Getting Closer"
        case .receding: return "Moving Away"
        case .stable: return "Signal Steady"
        }
    }

    private var trendIcon: String {
        switch contact.trend {
        case .approaching: return "arrow.up.circle.fill"
        case .receding: return "arrow.down.circle.fill"
        case .stable: return "equal.circle.fill"
        }
    }

    private var trendColor: Color {
        switch contact.trend {
        case .approaching: return .green
        case .receding: return .red
        case .stable: return .white.opacity(0.5)
        }
    }

    // MARK: - Bottom Panel

    @State private var showDetails = false

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showDetails.toggle()
                }
            } label: {
                HStack(spacing: 0) {
                    // Proximity ring
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.08), lineWidth: 5)
                            .frame(width: 52, height: 52)

                        Circle()
                            .trim(from: 0, to: signalStrength)
                            .stroke(
                                AngularGradient(
                                    colors: [proximityColor.opacity(0.4), proximityColor],
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round)
                            )
                            .frame(width: 52, height: 52)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.5), value: signalStrength)

                        Text("\(Int(signalStrength * 100))")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(proximityColor)
                    }
                    .padding(.leading, 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(distanceText)
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)

                        Text(contact.distance.rawValue)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.leading, 14)

                    Spacer()

                    VStack(spacing: 2) {
                        Image(systemName: trendIcon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(trendColor)

                        Text(trendLabel)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(trendColor.opacity(0.8))
                    }
                    .padding(.trailing, 16)

                    Image(systemName: "chevron.compact.down")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.3))
                        .rotationEffect(.degrees(showDetails ? 180 : 0))
                        .padding(.trailing, 14)
                }
                .padding(.vertical, 16)
            }
            .buttonStyle(.plain)

            if showDetails {
                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.horizontal, 16)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: [.red, .orange, .yellow, .green],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, geo.size.width * signalStrength), height: 4)
                            .animation(.easeInOut(duration: 0.3), value: signalStrength)
                    }
                }
                .frame(height: 4)
                .padding(.horizontal, 20)
                .padding(.top, 14)

                HStack(spacing: 0) {
                    detailItem(value: "\(contact.rssi)", unit: "dBm", label: "Signal")
                    detailDivider
                    detailItem(value: String(format: "%.1f", distanceMeters), unit: "m", label: "Distance")
                    detailDivider
                    detailItem(value: "\(sharedLandmarks)", unit: "", label: "Landmarks")
                    detailDivider
                    detailItem(value: "\(hopCount)", unit: "", label: "Hops")
                }
                .padding(.top, 12)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(.ultraThinMaterial)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.35), .white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
    }

    private var detailDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 0.5, height: 32)
    }

    private func detailItem(value: String, unit: String, label: String) -> some View {
        VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                    .foregroundColor(.white)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
    }

    private var distanceText: String {
        if distanceMeters < 1 { return "<1m" }
        else if distanceMeters < 10 { return String(format: "%.1fm", distanceMeters) }
        else { return String(format: "%.0fm", distanceMeters) }
    }

    private var trendLabel: String {
        switch contact.trend {
        case .approaching: return "CLOSER"
        case .receding: return "FARTHER"
        case .stable: return "STABLE"
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

    // MARK: - Logging

    private func logUpdate() {
        logCounter += 1
        if logCounter % 5 == 0 {
            print("[Radar UI] RSSI=\(contact.rssi) signal=\(String(format: "%.0f", signalStrength * 100))% dist=\(String(format: "%.1f", distanceMeters))m trend=\(contact.trend.rawValue) landmarks=\(sharedLandmarks) hops=\(hopCount)")
        }
    }
}
