import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ImageIO // <-- Add this here
struct ChatView: View {

    @EnvironmentObject private var store: ChatStore
    @EnvironmentObject private var bluetooth: BluetoothManager
    @StateObject private var audioManager = AudioManager()
    let peerId: String

    @State private var draft = ""
    @State private var typingSent = false
    @State private var typingResetWork: DispatchWorkItem?
    @State private var showFileImporter = false
    @State private var micPermissionDenied = false

    private var isConnected: Bool {
        bluetooth.connectedPeerIds.contains(peerId)
    }

    private var peerIsTyping: Bool {
        store.typingPeers.contains(peerId)
    }

    private var isGroup: Bool { store.isGroup(peerId) }
    private var memberCount: Int { store.groupMembers(peerId).count }

    var body: some View {
        ZStack {
            MeshBackground()
            VStack(spacing: 0) {
                messageList
                inputBar
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(store.conversationName(for: peerId))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(statusLabel)
                        .font(.caption2)
                        .foregroundStyle(statusColor)
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
            if audioManager.isRecording {
                _ = audioManager.stopRecording()
            }
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
        .preferredColorScheme(.dark)
    }

    private var statusColor: Color {
        if peerIsTyping { return Color(hex: 0xA855F7) }
        if isConnected { return Color(hex: 0x10B981) }
        return .white.opacity(0.45)
    }

    private var statusLabel: String {
        if isGroup { return "\(memberCount) members" }
        if peerIsTyping { return "typing..." }
        return isConnected ? "connected" : "not connected"
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(store.messages(for: peerId)) { message in
                        MessageBubble(message: message, showSender: isGroup)
                            .id(message.id)
                            .contextMenu {
                                if message.attachmentPath == nil {
                                    Button {
                                        UIPasteboard.general.string = message.body
                                    } label: {
                                        Label("Copy", systemImage: "doc.on.doc")
                                    }
                                }
                                Button(role: .destructive) {
                                    store.deleteMessage(id: message.id, peerId: peerId)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
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
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if !isGroup {
                Button {
                    showFileImporter = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            TextField("Message", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22)
                                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                        )
                )
                .onChange(of: draft) { value in
                    draftChanged(value)
                }
            if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGroup {
                micButton
            } else {
                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(
                            draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? AnyShapeStyle(.white.opacity(0.3))
                                : AnyShapeStyle(BlueTalkTheme.accentGradient)
                        )
                        .shadow(color: Color(hex: 0x6366F1).opacity(0.5), radius: 6)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.03))
                )
                .overlay(alignment: .top) {
                    Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5)
                }
        )
        .alert("Microphone Access", isPresented: $micPermissionDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Enable microphone access in Settings to send voice memos.")
        }
    }

    private var micButton: some View {
        Button {
            if audioManager.isRecording {
                finishRecording()
            } else {
                beginRecording()
            }
        } label: {
            Image(systemName: audioManager.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(audioManager.isRecording ? Color(hex: 0xF43F5E) : .white.opacity(0.6))
                .shadow(
                    color: audioManager.isRecording ? Color(hex: 0xF43F5E).opacity(0.5) : .clear,
                    radius: 8
                )
        }
    }

    private func beginRecording() {
        AudioManager.requestPermission { granted in
            if granted {
                audioManager.startRecording()
            } else {
                micPermissionDenied = true
            }
        }
    }

    private func finishRecording() {
        guard let url = audioManager.stopRecording() else { return }
        bluetooth.sendAttachment(peerId: peerId, url: url)
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
        if isGroup { return }
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
            VStack(alignment: message.isMine ? .trailing : .leading, spacing: 3) {
                if showSender, !message.isMine, let sender = message.senderName, !sender.isEmpty {
                    Text(sender)
                        .font(.caption.bold())
                        .foregroundStyle(Color(hex: 0xA855F7))
                        .padding(.leading, 4)
                }
                VStack(alignment: .trailing, spacing: 2) {
                    attachmentContent
                    HStack(spacing: 4) {
                        Text(message.timestamp, format: .dateTime.hour().minute())
                            .font(.caption2)
                        if message.isMine {
                            Text(ticks)
                                .font(.caption2)
                                .foregroundStyle(
                                    message.status == .read
                                        ? Color(hex: 0x06B6D4)
                                        : .white.opacity(0.5)
                                )
                        }
                    }
                    .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(bubbleBackground)
            }
            if !message.isMine { Spacer(minLength: 48) }
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.isMine {
            RoundedRectangle(cornerRadius: 20)
                .fill(BlueTalkTheme.sendBubbleGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.white.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                )
                .shadow(color: Color(hex: 0x6366F1).opacity(0.3), radius: 8, y: 3)
        } else {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                )
        }
    }

    @ViewBuilder
    private var attachmentContent: some View {
        if let path = message.attachmentPath,
           message.attachmentMime?.hasPrefix("image/") == true {
            
            // Use the new memory-safe view here
            AttachmentImageView(path: path)
            
        } else if let path = message.attachmentPath,
                  message.attachmentMime?.hasPrefix("audio/") == true {
            AudioPlaybackView(path: path, isMine: message.isMine)
        } else if message.attachmentPath != nil {
            Text("\(message.attachmentName ?? message.body)")
                .foregroundStyle(.white)
        } else {
            Text(message.body)
                .foregroundStyle(.white)
        }
    }

    private var ticks: String {
        switch message.status {
        case .pending: return "○"
        case .sent: return "✓"
        case .delivered, .read: return "✓✓"
        }
    }
}

private struct TypingBubble: View {

    @State private var phase: CGFloat = 0

    var body: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(.white.opacity(0.7))
                        .frame(width: 7, height: 7)
                        .offset(y: sin(phase + Double(i) * 0.8) * 3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                    )
            )
            Spacer()
        }
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

private struct AudioPlaybackView: View {

    let path: String
    let isMine: Bool
    @State private var playing = false
    @State private var player: AVAudioPlayer?

    var body: some View {
        Button {
            togglePlayback()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.body)
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(0.4))
                    .frame(height: 3)
                    .frame(maxWidth: 80)
                Text("Voice Memo")
                    .font(.caption)
            }
            .foregroundStyle(.white.opacity(0.9))
        }
        .onDisappear {
            player?.stop()
            player = nil
            playing = false
        }
    }

    private func togglePlayback() {
        if playing {
            player?.stop()
            playing = false
        } else {
            let url = URL(fileURLWithPath: path)
            player = try? AVAudioPlayer(contentsOf: url)
            player?.play()
            playing = true
        }
    }
}
private struct AttachmentImageView: View {
    let path: String
    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFit()
            } else {
                // Placeholder while loading
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .overlay(ProgressView())
            }
        }
        .frame(maxWidth: 220, maxHeight: 280)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .task(id: path) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        let url = URL(fileURLWithPath: path)
        let targetSize = CGSize(width: 220, height: 280)
        
        // Detach to a background thread to prevent UI freezing
        let imageRequest = Task.detached(priority: .userInitiated) { () -> UIImage? in
            let scale = await UIScreen.main.scale
            let options = [kCGImageSourceShouldCache: false] as CFDictionary
            
            guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else {
                return nil
            }
            
            let maxPixelSize = max(targetSize.width, targetSize.height) * scale
            let downsampleOptions = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ] as CFDictionary
            
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
                return nil
            }
            
            return UIImage(cgImage: cgImage)
        }
        
        self.thumbnail = await imageRequest.value
    }
}
