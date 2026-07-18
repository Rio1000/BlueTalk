import SwiftUI

struct ConversationsView: View {

    @EnvironmentObject private var store: ChatStore
    @EnvironmentObject private var bluetooth: BluetoothManager
    @State private var showDiscover = false
    @State private var showSettings = false
    @State private var showCreateGroup = false

    var body: some View {
        NavigationStack {
            ZStack {
                MeshBackground()
                Group {
                    if store.sortedConversations.isEmpty {
                        emptyState
                    } else {
                        conversationList
                    }
                }
            }
            .navigationTitle("BlueTalk")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(.white.opacity(0.85))
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
                            .foregroundStyle(.white.opacity(0.85))
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
        .preferredColorScheme(.dark)
    }

    private var conversationList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(store.sortedConversations) { conversation in
                    NavigationLink(value: conversation.peerId) {
                        ConversationRow(conversation: conversation)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .navigationDestination(for: String.self) { peerId in
            ChatView(peerId: peerId)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(BlueTalkTheme.accentGradient)
                .shadow(color: Color(hex: 0x6366F1).opacity(0.5), radius: 20)
            Text("No conversations yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("Tap the compose button to find a nearby device and start messaging over Bluetooth.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(28)
        .glassCard(cornerRadius: 24)
        .padding(.horizontal, 24)
    }
}

private struct ConversationRow: View {

    @EnvironmentObject private var store: ChatStore
    @EnvironmentObject private var bluetooth: BluetoothManager
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 14) {
            AvatarView(
                name: conversation.name,
                connected: bluetooth.connectedPeerIds.contains(conversation.peerId)
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(previewText)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(conversation.lastActivity, format: timestampFormat)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
                let unread = store.unreadCount(for: conversation.peerId)
                if unread > 0 {
                    Text("\(unread)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(BlueTalkTheme.accentGradient)
                        )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassCard(cornerRadius: 16)
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

    var body: some View {
        let idx = abs(name.hashValue) % BlueTalkTheme.avatarGradients.count
        let colors = BlueTalkTheme.avatarGradients[idx]
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(
                    LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 48, height: 48)
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                )
                .overlay {
                    Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                }
                .shadow(color: colors[0].opacity(0.4), radius: 6, y: 2)
            if connected {
                Circle()
                    .fill(Color(hex: 0x10B981))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(Color(hex: 0x0F0B1E), lineWidth: 2.5))
            }
        }
    }
}
