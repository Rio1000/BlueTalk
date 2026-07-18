import SwiftUI

struct CreateGroupView: View {

    @EnvironmentObject private var store: ChatStore
    @EnvironmentObject private var bluetooth: BluetoothManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selected: Set<String> = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Group name", text: $name)
                }
                Section {
                    let contacts = store.directContacts
                    if contacts.isEmpty {
                        Text("Chat with someone one-to-one first — your contacts show up here to add to a group.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(contacts) { contact in
                            Button {
                                if selected.contains(contact.peerId) {
                                    selected.remove(contact.peerId)
                                } else {
                                    selected.insert(contact.peerId)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    AvatarView(name: contact.name, connected: false)
                                    Text(contact.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: selected.contains(contact.peerId)
                                        ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected.contains(contact.peerId) ? .blue : .secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Add members")
                }
            }
            .navigationTitle("New group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        _ = bluetooth.createGroup(name: name, memberPeerIds: Array(selected))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || selected.isEmpty)
                }
            }
        }
    }
}
