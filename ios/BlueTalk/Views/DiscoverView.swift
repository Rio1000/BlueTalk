import SwiftUI

struct DiscoverView: View {

    @EnvironmentObject private var store: ChatStore
    @EnvironmentObject private var bluetooth: BluetoothManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(
                        "Your phone is advertising as “\(store.displayName)”. " +
                        "Ask your friend to open BlueTalk and scan — or scan " +
                        "yourself and tap their device below. Keep both apps " +
                        "in the foreground while connecting."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Section {
                    if bluetooth.discovered.isEmpty {
                        Text(bluetooth.scanning ? "Searching…" : "No devices found yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(bluetooth.discovered) { peer in
                            Button {
                                bluetooth.connect(to: peer.id)
                            } label: {
                                HStack(spacing: 12) {
                                    AvatarView(name: peer.name ?? "?", connected: false)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(peer.name ?? "Unknown device")
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text("Signal: \(peer.rssi) dBm")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if bluetooth.connecting.contains(peer.id) {
                                        ProgressView()
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Nearby devices")
                        Spacer()
                        if bluetooth.scanning {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
            }
            .navigationTitle("New chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(bluetooth.scanning ? "Stop" : "Scan") {
                        if bluetooth.scanning {
                            bluetooth.stopScan()
                        } else {
                            bluetooth.startScan()
                        }
                    }
                }
            }
            .onAppear { bluetooth.startScan() }
            .onDisappear { bluetooth.stopScan() }
            .onChange(of: bluetooth.connectedPeerIds) { _ in
                // A link came up while this sheet is open: the conversation
                // now exists, so hand the user back to the list to open it.
                if !bluetooth.connectedPeerIds.isEmpty {
                    dismiss()
                }
            }
        }
    }
}
