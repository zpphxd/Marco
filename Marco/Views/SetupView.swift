import SwiftUI

struct SetupView: View {
    @ObservedObject var viewModel: RadarViewModel
    @State private var animateIcon = false

    private var canStart: Bool {
        !viewModel.myHash.isEmpty && viewModel.contactManager.isAuthorized
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 52))
                        .foregroundColor(.blue)
                        .scaleEffect(animateIcon ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: animateIcon)
                        .onAppear { animateIcon = true }

                    Text("Marco")
                        .font(.largeTitle.weight(.bold))

                    Text("Find your people when it matters most")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 30)

                // Phone number card
                VStack(alignment: .leading, spacing: 10) {
                    Label("Your Phone Number", systemImage: "phone.fill")
                        .font(.headline)

                    TextField("e.g. 555-123-4567", text: $viewModel.myPhoneNumber)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        #if os(iOS)
                        .keyboardType(.phonePad)
                        #endif

                    if !viewModel.myHash.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.shield.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                            Text(viewModel.myHash)
                                .font(.caption2.monospaced())
                                .foregroundColor(.secondary)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Text("Hashed locally. Never stored or sent as plain text.")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                // Permissions card
                VStack(alignment: .leading, spacing: 14) {
                    Label("Permissions", systemImage: "checkmark.shield.fill")
                        .font(.headline)

                    PermissionRow(
                        icon: "dot.radiowaves.left.and.right",
                        title: "Bluetooth",
                        status: bluetoothStatus,
                        isGranted: viewModel.centralManager.bluetoothState == .poweredOn
                    )

                    HStack {
                        PermissionRow(
                            icon: "person.2.fill",
                            title: "Contacts",
                            status: viewModel.contactManager.isAuthorized
                                ? "\(viewModel.contactManager.hashCount) contacts hashed"
                                : "Required for matching",
                            isGranted: viewModel.contactManager.isAuthorized
                        )

                        if !viewModel.contactManager.isAuthorized {
                            Button("Grant") {
                                Task { await viewModel.contactManager.requestAccess() }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }

                    if viewModel.uwbManager.isSupported {
                        PermissionRow(
                            icon: "scope",
                            title: "Ultra-Wideband",
                            status: "Precision direction finding",
                            isGranted: true
                        )
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                // Start button
                Button {
                    viewModel.startRadar()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text("Start Scanning")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(!canStart)
                .padding(.horizontal)

                if !canStart && viewModel.myHash.isEmpty {
                    Text("Enter your phone number to begin")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                Spacer(minLength: 40)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.myHash.isEmpty)
        .animation(.easeInOut(duration: 0.3), value: viewModel.contactManager.isAuthorized)
    }

    private var bluetoothStatus: String {
        switch viewModel.centralManager.bluetoothState {
        case .poweredOn: return "Ready"
        case .poweredOff: return "Turn on Bluetooth"
        case .unauthorized: return "Permission denied"
        case .unsupported: return "Not supported"
        default: return "Initializing..."
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let status: String
    let isGranted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .frame(width: 28)
                .foregroundColor(isGranted ? .green : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(status)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundColor(isGranted ? .green : .orange)
                .font(.system(size: 18))
        }
    }
}
