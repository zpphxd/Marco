import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = RadarViewModel()
    @State private var showSetup = false
    @State private var showDemo = false
    @State private var pulseActive = false

    var body: some View {
        NavigationStack {
            ZStack {
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
            // Radar button + status
            radarHeader
                .padding(.vertical, 24)

            // Stats bar
            if viewModel.isRadarActive {
                statsBar
                    .padding(.horizontal)
                    .padding(.bottom, 12)
            }

            Divider()

            // Contact list
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

    private var statsBar: some View {
        HStack(spacing: 12) {
            StatPill(icon: "person.2", value: "\(viewModel.contactManager.hashCount)", label: "Contacts")
            StatPill(icon: "mappin.and.ellipse", value: "\(viewModel.landmarkTracker.landmarkCount)", label: "Landmarks")
            StatPill(icon: "point.3.connected.trianglepath.dotted", value: "\(viewModel.meshManager?.connectedPeers ?? 0)", label: "Mesh")

            let knownCount = viewModel.nearbyContacts.filter { $0.phoneNumber != nil }.count
            StatPill(icon: "person.crop.circle.badge.checkmark", value: "\(knownCount)", label: "Found")
                .foregroundColor(knownCount > 0 ? .green : .secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "person.wave.2")
                .font(.system(size: 56))
                .foregroundColor(.secondary.opacity(0.5))

            Text("Scanning for nearby contacts...")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Other devices need Contact Radar running")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.7))

            ProgressView()
                .padding(.top, 8)

            Spacer()
        }
        .padding()
    }

    private var readyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Tap the antenna to start scanning")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Your hash: \(viewModel.myHash.prefix(8))...")
                .font(.caption.monospaced())
                .foregroundColor(.secondary)

            Spacer()
        }
    }

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
                            NearbyContactRow(contact: contact)
                        }
                    }
                } header: {
                    Label("Contacts Found", systemImage: "person.crop.circle.badge.checkmark")
                        .foregroundColor(.green)
                }
            }

            if !unknown.isEmpty {
                Section("Other Devices") {
                    ForEach(unknown) { contact in
                        NearbyContactRow(contact: contact)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
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
}

// MARK: - Supporting Views

struct StatPill: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
