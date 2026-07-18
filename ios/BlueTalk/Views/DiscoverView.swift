import SwiftUI

struct DiscoverView: View {

    @EnvironmentObject private var store: ChatStore
    @EnvironmentObject private var bluetooth: BluetoothManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                MeshBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        HStack(spacing: 10) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundStyle(Color(hex: 0x06B6D4))
                            Text(
                                "Your phone is advertising as \"\(store.displayName)\". " +
                                "Tap a device below to connect."
                            )
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                        }
                        .padding(16)
                        .glassCard(cornerRadius: 14)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Nearby devices")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.6))
                                Spacer()
                                if bluetooth.scanning {
                                    ProgressView()
                                        .tint(.white.opacity(0.5))
                                        .controlSize(.small)
                                }
                            }
                            .padding(.horizontal, 4)

                            if bluetooth.discovered.isEmpty {
                                HStack {
                                    Spacer()
                                    VStack(spacing: 8) {
                                        if bluetooth.scanning {
                                            ProgressView()
                                                .tint(Color(hex: 0x6366F1))
                                            Text("Searching...")
                                                .font(.subheadline)
                                                .foregroundStyle(.white.opacity(0.5))
                                        } else {
                                            Image(systemName: "magnifyingglass")
                                                .font(.title2)
                                                .foregroundStyle(.white.opacity(0.3))
                                            Text("No devices found yet")
                                                .font(.subheadline)
                                                .foregroundStyle(.white.opacity(0.5))
                                        }
                                    }
                                    .padding(.vertical, 30)
                                    Spacer()
                                }
                                .glassCard(cornerRadius: 16)
                            } else {
                                ForEach(bluetooth.discovered) { peer in
                                    Button {
                                        bluetooth.connect(to: peer.id)
                                    } label: {
                                        HStack(spacing: 14) {
                                            AvatarView(name: peer.name ?? "?", connected: false)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(peer.name ?? "Unknown device")
                                                    .font(.body.weight(.medium))
                                                    .foregroundStyle(.white)
                                                HStack(spacing: 4) {
                                                    Image(systemName: "wave.3.right")
                                                        .font(.caption2)
                                                    Text("\(peer.rssi) dBm")
                                                        .font(.caption)
                                                }
                                                .foregroundStyle(.white.opacity(0.4))
                                            }
                                            Spacer()
                                            if bluetooth.connecting.contains(peer.id) {
                                                ProgressView()
                                                    .tint(Color(hex: 0xA855F7))
                                            } else {
                                                Image(systemName: "chevron.right")
                                                    .font(.caption)
                                                    .foregroundStyle(.white.opacity(0.3))
                                            }
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                        .glassCard(cornerRadius: 16)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("New chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white.opacity(0.8))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(bluetooth.scanning ? "Stop" : "Scan") {
                        if bluetooth.scanning {
                            bluetooth.stopScan()
                        } else {
                            bluetooth.startScan()
                        }
                    }
                    .foregroundStyle(Color(hex: 0xA855F7))
                }
            }
            .onAppear { bluetooth.startScan() }
            .onDisappear { bluetooth.stopScan() }
            .onChange(of: bluetooth.connectedPeerIds) { _ in
                if !bluetooth.connectedPeerIds.isEmpty {
                    dismiss()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
