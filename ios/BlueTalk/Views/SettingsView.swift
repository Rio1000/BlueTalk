import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var store: ChatStore
    @EnvironmentObject private var bluetooth: BluetoothManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Display name", text: $name)
                } header: {
                    Text("Display name")
                } footer: {
                    Text("Shown to the people you chat with.")
                }

                Section {
                    Text(
                        "BlueTalk exchanges messages directly between phones " +
                        "over Bluetooth Low Energy — no cellular network, Wi-Fi " +
                        "or servers involved. Messages you send while a contact " +
                        "is out of range are queued and delivered the next time " +
                        "you connect."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
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
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { name = store.displayName }
        }
    }
}
