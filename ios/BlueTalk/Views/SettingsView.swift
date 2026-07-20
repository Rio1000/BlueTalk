import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var store: ChatStore
    @EnvironmentObject private var bluetooth: BluetoothManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""

    var body: some View {
        NavigationStack {
            ZStack {
                MeshBackground()
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Display name", systemImage: "person.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.7))
                            TextField("Your name", text: $name)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .foregroundStyle(.white)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(.ultraThinMaterial)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14)
                                                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                                        )
                                )
                            Text("Shown to the people you chat with.")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .padding(18)
                        .glassCard(cornerRadius: 18)

                        VStack(alignment: .leading, spacing: 12) {
                            Label("About", systemImage: "info.circle.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.7))
                            Text(
                                "ConnectBlue exchanges messages directly between phones " +
                                "over Bluetooth Low Energy \u{2014} no cellular network, Wi-Fi " +
                                "or servers involved. Messages you send while a contact " +
                                "is out of range are queued and delivered the next time " +
                                "you connect."
                            )
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                            .lineSpacing(3)
                        }
                        .padding(18)
                        .glassCard(cornerRadius: 18)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.8))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            store.displayName = trimmed
                            bluetooth.displayNameChanged(trimmed)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        name.trimmingCharacters(in: .whitespaces).isEmpty
                            ? .white.opacity(0.3) : Color(hex: 0xA855F7)
                    )
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { name = store.displayName }
        }
        .preferredColorScheme(.dark)
    }
}
