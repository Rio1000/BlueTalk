import SwiftUI

struct CreateGroupView: View {

    @EnvironmentObject private var store: ChatStore
    @EnvironmentObject private var bluetooth: BluetoothManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selected: Set<String> = []

    var body: some View {
        NavigationStack {
            ZStack {
                MeshBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Group name", systemImage: "bubble.left.and.bubble.right.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.7))
                            TextField("Enter a name", text: $name)
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
                        }
                        .padding(16)
                        .glassCard(cornerRadius: 18)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Add members")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.horizontal, 4)

                            let contacts = store.directContacts
                            if contacts.isEmpty {
                                HStack {
                                    Spacer()
                                    Text("Chat with someone one-to-one first to add them here.")
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.4))
                                        .multilineTextAlignment(.center)
                                        .padding(.vertical, 24)
                                    Spacer()
                                }
                                .glassCard(cornerRadius: 16)
                            } else {
                                ForEach(contacts) { contact in
                                    Button {
                                        if selected.contains(contact.peerId) {
                                            selected.remove(contact.peerId)
                                        } else {
                                            selected.insert(contact.peerId)
                                        }
                                    } label: {
                                        HStack(spacing: 14) {
                                            AvatarView(name: contact.name, connected: false)
                                            Text(contact.name)
                                                .font(.body)
                                                .foregroundStyle(.white)
                                            Spacer()
                                            Image(
                                                systemName: selected.contains(contact.peerId)
                                                    ? "checkmark.circle.fill" : "circle"
                                            )
                                            .font(.title3)
                                            .foregroundStyle(
                                                selected.contains(contact.peerId)
                                                    ? Color(hex: 0xA855F7) : .white.opacity(0.3)
                                            )
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .glassCard(cornerRadius: 14)
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
            .navigationTitle("New group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.8))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        _ = bluetooth.createGroup(name: name, memberPeerIds: Array(selected))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        (name.trimmingCharacters(in: .whitespaces).isEmpty || selected.isEmpty)
                            ? .white.opacity(0.3) : Color(hex: 0xA855F7)
                    )
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || selected.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
