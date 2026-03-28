import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = RadarViewModel()
    @State private var showSetup = false
    @State private var showDemo = false
    @State private var pulseActive = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Dark background when scanning
                if viewModel.isRadarActive {
                    Color.black.opacity(0.03).ignoresSafeArea()
                }

                if !viewModel.isRadarActive && viewModel.myHash.isEmpty {
                    SetupView(viewModel: viewModel)
                } else {
                    radarView
                }
            }
            .navigationTitle("Marco")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showDemo = true
                    } label: {
                        Image(systemName: "play.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !viewModel.myHash.isEmpty {
                        Button {
                            showSetup.toggle()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showDemo) {
                DemoRadarView()
            }
            .sheet(isPresented: $showSetup) {
                NavigationStack {
                    SetupView(viewModel: viewModel)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showSetup = false }
                            }
                        }
                }
            }
        }
    }

    // MARK: - Radar View

    private var radarView: some View {
        VStack(spacing: 0) {
            radarHeader
                .padding(.vertical, 24)

            if viewModel.isRadarActive {
                statsBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }

            Divider()

            if viewModel.isRadarActive {
                if viewModel.nearbyContacts.isEmpty {
                    emptyState
                } else {
                    contactList
                }
            } else {
                readyState
            }
        }
    }

    // MARK: - Radar Header

    private var radarHeader: some View {
        VStack(spacing: 12) {
            Button(action: toggleRadar) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.12))
                        .frame(width: 120, height: 120)

                    if viewModel.isRadarActive {
                        Circle()
                            .stroke(statusColor.opacity(0.3), lineWidth: 2)
                            .frame(width: 140, height: 140)
                            .scaleEffect(pulseActive ? 1.3 : 1.0)
                            .opacity(pulseActive ? 0 : 0.6)
                            .onAppear {
                                withAnimation(
                                    .easeOut(duration: 1.5)
                                    .repeatForever(autoreverses: false)
                                ) {
                                    pulseActive = true
                                }
                            }
                            .onDisappear {
                                pulseActive = false
                            }
                    }

                    Image(systemName: viewModel.isRadarActive
                        ? "antenna.radiowaves.left.and.right"
                        : "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 44))
                        .foregroundColor(statusColor)
                }
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.contactManager.isAuthorized)

            Text(viewModel.status.rawValue)
                .font(.title3.weight(.semibold))
                .foregroundColor(statusColor)

            if !viewModel.contactManager.isAuthorized {
                Button("Grant Contacts Access") {
                    Task { await viewModel.contactManager.requestAccess() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: 8) {
            statCard(
                icon: "person.2.fill",
                value: "\(viewModel.contactManager.hashCount)",
                label: "Contacts",
                color: .blue
            )
            statCard(
                icon: "mappin.and.ellipse",
                value: "\(viewModel.landmarkTracker.landmarkCount)",
                label: "Landmarks",
                color: .purple
            )
            statCard(
                icon: "point.3.connected.trianglepath.dotted",
                value: "\(viewModel.centralManager.connectedPeerCount)",
                label: "Mesh Peers",
                color: .orange
            )

            let knownCount = viewModel.nearbyContacts.filter { $0.phoneNumber != nil }.count
            statCard(
                icon: "person.crop.circle.badge.checkmark",
                value: "\(knownCount)",
                label: "Found",
                color: knownCount > 0 ? .green : .secondary
            )
        }
    }

    private func statCard(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)

            Text(value)
                .font(.system(.title3, design: .monospaced).weight(.bold))

            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "person.wave.2")
                .font(.system(size: 56))
                .foregroundColor(.secondary.opacity(0.4))

            Text("Scanning for nearby contacts...")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Other devices need Marco running")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.6))

            // Live mesh info
            if viewModel.centralManager.connectedPeerCount > 0 {
                HStack(spacing: 12) {
                    Label("\(viewModel.centralManager.connectedPeerCount) peers", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.5))
                .padding(.top, 4)
            }

            ProgressView()
                .padding(.top, 8)

            Spacer()
        }
        .padding()
    }

    // MARK: - Ready State

    private var readyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Tap the antenna to start scanning")
                .font(.headline)
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                Text("Your ID:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(String(viewModel.myHash.prefix(8)) + "...")
                    .font(.caption.monospaced())
                    .foregroundColor(.blue)
            }

            Spacer()
        }
    }

    // MARK: - Contact List

    private var contactList: some View {
        List {
            let known = viewModel.nearbyContacts.filter { $0.phoneNumber != nil }
            let unknown = viewModel.nearbyContacts.filter { $0.phoneNumber == nil }

            if !known.isEmpty {
                Section {
                    ForEach(known) { contact in
                        NavigationLink {
                            FindMyRadarView(
                                contactID: contact.id,
                                viewModel: viewModel,
                                sharedLandmarks: viewModel.landmarkTracker.landmarkCount,
                                hopCount: contact.id.hasPrefix("mesh-") ? 1 : 0
                            )
                        } label: {
                            contactRow(contact)
                        }
                    }
                } header: {
                    Label("Contacts Found", systemImage: "person.crop.circle.badge.checkmark")
                        .foregroundColor(.green)
                }
            }

            if !unknown.isEmpty {
                Section("Other Marco Devices") {
                    ForEach(unknown) { contact in
                        contactRow(contact)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func contactRow(_ contact: NearbyContact) -> some View {
        HStack(spacing: 12) {
            // Proximity indicator
            ZStack {
                Circle()
                    .fill(distanceColor(contact.distance).opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: contact.phoneNumber != nil ? "person.fill" : "antenna.radiowaves.left.and.right")
                    .font(.system(size: 16))
                    .foregroundColor(distanceColor(contact.distance))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(contact.name)
                    .font(.body.weight(.medium))

                HStack(spacing: 6) {
                    Text(contact.distance.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if contact.id.hasPrefix("mesh-") {
                        Text("via mesh")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            // Trend
            VStack(alignment: .trailing, spacing: 2) {
                Image(systemName: trendIcon(contact.trend))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(trendColor(contact.trend))

                Text("\(contact.rssi) dBm")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            if contact.phoneNumber != nil {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.5))
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func toggleRadar() {
        if viewModel.isRadarActive {
            viewModel.stopRadar()
        } else {
            viewModel.startRadar()
        }
    }

    private var statusColor: Color {
        switch viewModel.status {
        case .off: return .secondary
        case .scanning: return .blue
        case .found: return .green
        }
    }

    private func distanceColor(_ distance: DistanceEstimate) -> Color {
        switch distance {
        case .veryClose: return .green
        case .nearby: return .yellow
        case .inRange: return .orange
        case .far: return .red
        case .unknown: return .gray
        }
    }

    private func trendIcon(_ trend: NearbyContact.Trend) -> String {
        switch trend {
        case .approaching: return "arrow.up.right"
        case .receding: return "arrow.down.right"
        case .stable: return "equal"
        }
    }

    private func trendColor(_ trend: NearbyContact.Trend) -> Color {
        switch trend {
        case .approaching: return .green
        case .receding: return .red
        case .stable: return .secondary
        }
    }
}
