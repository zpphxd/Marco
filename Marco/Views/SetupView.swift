import SwiftUI

struct SetupView: View {
    @ObservedObject var viewModel: RadarViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)

                    Text("Marco")
                        .font(.largeTitle.weight(.bold))

                    Text("Find your people when it matters most.\nNo internet needed.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)

                // Phone number
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Phone Number")
                        .font(.headline)

                    Text("Hashed locally — never stored or sent as plain text")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("e.g. 555-123-4567", text: $viewModel.myPhoneNumber)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.phonePad)
                        #endif

                    if !viewModel.myHash.isEmpty {
                        HStack {
                            Text("Your hash:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(viewModel.myHash)
                                .font(.caption.monospaced())
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding(.horizontal)

                Divider()
                    .padding(.horizontal)

                // Permissions
                VStack(alignment: .leading, spacing: 12) {
                    Text("Permissions")
                        .font(.headline)
                        .padding(.horizontal)

                    PermissionRow(
                        icon: "dot.radiowaves.left.and.right",
                        title: "Bluetooth",
                        status: bluetoothStatus,
                        isGranted: viewModel.centralManager.bluetoothState == .poweredOn
                    )
                    .padding(.horizontal)

                    HStack {
                        PermissionRow(
                            icon: "person.2",
                            title: "Contacts",
                            status: viewModel.contactManager.isAuthorized
                                ? "\(viewModel.contactManager.hashCount) hashes loaded"
                                : "Not authorized",
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
                    .padding(.horizontal)
                }

                Spacer()
            }
        }
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
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(isGranted ? .green : .orange)

            VStack(alignment: .leading) {
                Text(title)
                    .font(.subheadline)
                Text(status)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundColor(isGranted ? .green : .orange)
        }
    }
}
