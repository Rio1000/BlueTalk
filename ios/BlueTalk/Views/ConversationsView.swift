import SwiftUI

struct ConversationsView: View {

    @EnvironmentObject private var store: ChatStore
    @EnvironmentObject private var bluetooth: BluetoothManager
    @State private var showDiscover = false
    @State private var showSettings = false
    @State private var showCreateGroup = false

    var body: some View {
        NavigationStack {
            Group {
                if store.sortedConversations.isEmpty {
                    emptyState
                } else {
                    conversationList
                }
            }
            .navigationTitle("BlueTalk")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showDiscover = true
                        } label: {
                            Label("New chat", systemImage: "person.badge.plus")
                        }
                        Button {
                            showCreateGroup = true
                        } label: {
                            Label("New group", systemImage: "person.3")
                        }
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $showDiscover) {
                DiscoverView()
            }
            .sheet(isPresented: $showCreateGroup) {
                CreateGroupView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .task {
                LocalNotifications.requestAuthorization()
            }
        }
    }

    private var conversationList: some View {
        List {
            ForEach(store.sortedConversations) { conversation in
                NavigationLink(value: conversation.peerId) {
                    ConversationRow(conversation: conversation)
                }
            }
            .onDelete { offsets in
                let sorted = store.sortedConversations
                for offset in offsets {
                    store.deleteConversation(peerId: sorted[offset].peerId)
                }
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: String.self) { peerId in
            ChatView(peerId: peerId)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No conversations yet")
                .font(.headline)
            Text("Tap + to find a nearby device and start messaging over Bluetooth — no internet needed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

private struct ConversationRow: View {

    @EnvironmentObject private var store: ChatStore
    @EnvironmentObject private var bluetooth: BluetoothManager
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(
                name: conversation.name,
                connected: bluetooth.connectedPeerIds.contains(conversation.peerId)
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(previewText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(conversation.lastActivity, format: timestampFormat)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                let unread = store.unreadCount(for: conversation.peerId)
                if unread > 0 {
                    Text("\(unread)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Circle().fill(.blue))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var previewText: String {
        guard let last = store.lastMessage(for: conversation.peerId) else {
            return "No messages yet"
        }
        return last.isMine ? "You: \(last.body)" : last.body
    }

    private var timestampFormat: Date.FormatStyle {
        if Calendar.current.isDateInToday(conversation.lastActivity) {
            return .dateTime.hour().minute()
        }
        return .dateTime.day().month(.abbreviated)
    }
}

struct AvatarView: View {

    let name: String
    let connected: Bool

    private static let palette: [Color] = [
        .indigo, .teal, .red, .purple, .orange, .blue, .green, .brown,
    ]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(Self.palette[abs(name.hashValue) % Self.palette.count])
                .frame(width: 46, height: 46)
                .overlay {
                    Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            if connected {
                Circle()
                    .fill(.green)
                    .frame(width: 13, height: 13)
                    .overlay(Circle().stroke(.background, lineWidth: 2))
            }
        }
    }
}
