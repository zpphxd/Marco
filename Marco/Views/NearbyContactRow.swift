import SwiftUI

struct NearbyContactRow: View {
    let contact: NearbyContact

    var body: some View {
        HStack(spacing: 12) {
            // Distance color indicator
            Circle()
                .fill(distanceColor)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(contact.name)
                        .font(.headline)

                    if contact.phoneNumber != nil {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }

                Text(contact.distance.rawValue)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Trend arrow
            Image(systemName: contact.trend.symbol)
                .foregroundColor(trendColor)
                .font(.title3)

            // Navigate chevron
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private var distanceColor: Color {
        switch contact.distance {
        case .veryClose: return .green
        case .nearby: return .yellow
        case .inRange: return .orange
        case .far: return .red
        case .unknown: return .gray
        }
    }

    private var trendColor: Color {
        switch contact.trend {
        case .approaching: return .green
        case .receding: return .red
        case .stable: return .gray
        }
    }
}

struct SignalStrengthView: View {
    let rssi: Int

    private var bars: Int {
        switch rssi {
        case -50...0: return 4
        case -65...(-49): return 3
        case -80...(-64): return 2
        default: return 1
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...4, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 1)
                    .fill(bar <= bars ? Color.primary : Color.primary.opacity(0.2))
                    .frame(width: 4, height: CGFloat(bar * 4 + 4))
            }
        }
    }
}
