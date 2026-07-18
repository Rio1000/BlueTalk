import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ChatView: View {

    @EnvironmentObject private var store: ChatStore
    @EnvironmentObject private var bluetooth: BluetoothManager
    let peerId: String

    @State private var draft = ""
    @State private var typingSent = false
    @State private var typingResetWork: DispatchWorkItem?
    @State private var showFileImporter = false

    private var isConnected: Bool {
        bluetooth.connectedPeerIds.contains(peerId)
    }

    private var peerIsTyping: Bool {
        store.typingPeers.contains(peerId)
    }

    private var isGroup: Bool { store.isGroup(peerId) }
    private var memberCount: Int { store.groupMembers(peerId).count }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            inputBar
        }
        .navigationTitle(store.conversationName(for: peerId))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(store.conversationName(for: peerId))
                        .font(.headline)
                        .lineLimit(1)
                    Text(statusLabel)
                        .font(.caption2)
                        .foregroundStyle(peerIsTyping ? .blue : (isConnected ? .green : .secondary))
                }
            }
        }
        .onAppear {
            store.activePeerId = peerId
            bluetooth.markConversationSeen(peerId: peerId)
        }
        .onDisappear {
            if store.activePeerId == peerId {
                store.activePeerId = nil
            }
            stopTyping()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image, .data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                bluetooth.sendAttachment(peerId: peerId, url: url)
            }
        }
    }

    private var statusLabel: String {
        if isGroup { return "\(memberCount) members" }
        if peerIsTyping { return "typing…" }
        return isConnected ? "connected" : "not connected"
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(store.messages(for: peerId)) { message in
                        MessageBubble(message: message, showSender: isGroup)
                            .id(message.id)
                    }
                    if peerIsTyping {
                        TypingBubble()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: store.messages(for: peerId).count) { _ in
                scrollToBottom(proxy)
                bluetooth.markConversationSeen(peerId: peerId)
            }
            .onAppear { scrollToBottom(proxy) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let last = store.messages(for: peerId).last {
            withAnimation {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !isGroup {
                Button {
                    showFileImporter = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                }
            }
            TextField("Message", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(.secondarySystemBackground))
                )
                .onChange(of: draft) { value in
                    draftChanged(value)
                }
            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(10)
        .background(.bar)
    }

    private func send() {
        stopTyping()
        if isGroup {
            bluetooth.sendGroupMessage(groupId: peerId, body: draft)
        } else {
            bluetooth.sendMessage(peerId: peerId, body: draft)
        }
        draft = ""
    }

    private func draftChanged(_ value: String) {
        if isGroup { return } // Typing indicators are 1:1 only.
        if value.isEmpty {
            stopTyping()
            return
        }
        if !typingSent {
            typingSent = true
            bluetooth.sendTyping(peerId: peerId, active: true)
        }
        typingResetWork?.cancel()
        let work = DispatchWorkItem { stopTyping() }
        typingResetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private func stopTyping() {
        typingResetWork?.cancel()
        typingResetWork = nil
        if typingSent {
            typingSent = false
            bluetooth.sendTyping(peerId: peerId, active: false)
        }
    }
}

private struct MessageBubble: View {

    let message: ChatMessage
    var showSender: Bool = false

    var body: some View {
        HStack {
            if message.isMine { Spacer(minLength: 48) }
            VStack(alignment: .trailing, spacing: 2) {
                if showSender, !message.isMine, let sender = message.senderName, !sender.isEmpty {
                    Text(sender)
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                attachmentContent
                HStack(spacing: 4) {
                    Text(message.timestamp, format: .dateTime.hour().minute())
                        .font(.caption2)
                    if message.isMine {
                        Text(ticks)
                            .font(.caption2)
                            .foregroundStyle(
                                message.status == .read
                                    ? Color.cyan
                                    : (message.isMine ? Color.white.opacity(0.7) : Color.secondary)
                            )
                    }
                }
                .foregroundStyle(message.isMine ? Color.white.opacity(0.7) : Color.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(message.isMine ? Color.blue : Color(.secondarySystemBackground))
            )
            if !message.isMine { Spacer(minLength: 48) }
        }
    }

    @ViewBuilder
    private var attachmentContent: some View {
        if let path = message.attachmentPath,
           message.attachmentMime?.hasPrefix("image/") == true,
           let image = UIImage(contentsOfFile: path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 220, maxHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else if message.attachmentPath != nil {
            Text("📎 \(message.attachmentName ?? message.body)")
                .foregroundStyle(message.isMine ? .white : .primary)
        } else {
            Text(message.body)
                .foregroundStyle(message.isMine ? .white : .primary)
        }
    }

    private var ticks: String {
        switch message.status {
        case .pending: return "🕓"
        case .sent: return "✓"
        case .delivered, .read: return "✓✓"
        }
    }
}

private struct TypingBubble: View {

    @State private var pulsing = false

    var body: some View {
        HStack {
            Text("• • •")
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(.secondarySystemBackground))
                )
                .opacity(pulsing ? 1 : 0.35)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulsing)
            Spacer()
        }
        .onAppear { pulsing = true }
    }
}
