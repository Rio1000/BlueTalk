import Foundation

/// Owns all chat state: conversations, message history, unread counts and
/// the local profile. Persists to a JSON file in the app's Documents
/// directory so history survives relaunches.
///
/// All access happens on the main thread: SwiftUI drives the UI there and
/// the Bluetooth controllers deliver every callback on the main queue.
final class ChatStore: ObservableObject {

    @Published private(set) var conversations: [Conversation] = []
    @Published private(set) var messagesByPeer: [String: [ChatMessage]] = [:]
    @Published var typingPeers: Set<String> = []
    @Published var displayName: String {
        didSet { UserDefaults.standard.set(displayName, forKey: Self.nameKey) }
    }

    /// Whether the user has picked a display name (drives first-run onboarding).
    @Published private(set) var hasChosenName: Bool

    /// Conversation currently on screen; its incoming messages are auto-read.
    var activePeerId: String?

    /// Stable random identity for this install, announced in `hello`.
    let myPeerId: String

    private static let nameKey = "displayName"
    private static let peerIdKey = "peerId"
    private static let nameChosenKey = "nameChosen"

    private struct Snapshot: Codable {
        var conversations: [Conversation]
        var messagesByPeer: [String: [ChatMessage]]
    }

    init() {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: Self.peerIdKey) {
            myPeerId = existing
        } else {
            let generated = UUID().uuidString
            defaults.set(generated, forKey: Self.peerIdKey)
            myPeerId = generated
        }
        displayName = defaults.string(forKey: Self.nameKey) ?? UIDeviceName.current
        hasChosenName = defaults.bool(forKey: Self.nameChosenKey)
        load()
    }

    /// A sensible starting suggestion for the name-entry screen.
    var suggestedName: String { UIDeviceName.current }

    /// Records the name picked during first-run onboarding.
    func chooseName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        displayName = trimmed.isEmpty ? UIDeviceName.current : trimmed
        hasChosenName = true
        UserDefaults.standard.set(true, forKey: Self.nameChosenKey)
    }

    // MARK: - Queries

    var sortedConversations: [Conversation] {
        conversations.sorted { $0.lastActivity > $1.lastActivity }
    }

    func messages(for peerId: String) -> [ChatMessage] {
        messagesByPeer[peerId] ?? []
    }

    func unreadCount(for peerId: String) -> Int {
        messages(for: peerId).filter { !$0.isMine && !$0.isReadLocally }.count
    }

    func lastMessage(for peerId: String) -> ChatMessage? {
        messages(for: peerId).last
    }

    func conversationName(for peerId: String) -> String {
        conversations.first(where: { $0.peerId == peerId })?.name ?? "Unknown"
    }

    func isGroup(_ id: String) -> Bool {
        conversations.first(where: { $0.peerId == id })?.isGroup == true
    }

    func groupMembers(_ id: String) -> [String] {
        conversations.first(where: { $0.peerId == id })?.memberIds ?? []
    }

    /// 1:1 conversations, for the group member picker.
    var directContacts: [Conversation] {
        conversations.filter { $0.isGroup != true }
    }

    func pendingMessages(for peerId: String) -> [ChatMessage] {
        messages(for: peerId).filter { $0.isMine && $0.status == .pending }
    }

    // MARK: - Mutations

    func ensureConversation(peerId: String, name: String?) {
        if let index = conversations.firstIndex(where: { $0.peerId == peerId }) {
            if let name, !name.isEmpty, conversations[index].name != name {
                conversations[index].name = name
                save()
            }
        } else {
            conversations.append(
                Conversation(peerId: peerId, name: name ?? "Unknown", lastActivity: Date())
            )
            save()
        }
    }

    /// Creates and queues an outgoing message, returning it for sending.
    func recordOutgoing(peerId: String, body: String) -> ChatMessage {
        let message = ChatMessage(
            id: UUID().uuidString,
            peerId: peerId,
            body: body,
            timestamp: Date(),
            isMine: true,
            status: .pending,
            isReadLocally: true
        )
        append(message, to: peerId)
        return message
    }

    /// Inserts an incoming message unless its id is already known
    /// (peers re-send until acknowledged). Returns false for duplicates.
    @discardableResult
    func recordIncoming(id: String, peerId: String, body: String) -> Bool {
        guard !messages(for: peerId).contains(where: { $0.id == id }) else { return false }
        let message = ChatMessage(
            id: id,
            peerId: peerId,
            body: body,
            timestamp: Date(),
            isMine: false,
            status: .delivered,
            isReadLocally: activePeerId == peerId
        )
        append(message, to: peerId)
        return true
    }

    /// Creates and queues an outgoing attachment message.
    func recordOutgoingAttachment(
        peerId: String,
        path: String,
        name: String,
        mime: String
    ) -> ChatMessage {
        let message = ChatMessage(
            id: UUID().uuidString,
            peerId: peerId,
            body: name,
            timestamp: Date(),
            isMine: true,
            status: .pending,
            isReadLocally: true,
            attachmentPath: path,
            attachmentName: name,
            attachmentMime: mime
        )
        append(message, to: peerId)
        return message
    }

    /// Records a received attachment unless its id is already known.
    @discardableResult
    func recordIncomingAttachment(
        id: String,
        peerId: String,
        path: String,
        name: String,
        mime: String
    ) -> Bool {
        guard !messages(for: peerId).contains(where: { $0.id == id }) else { return false }
        let message = ChatMessage(
            id: id,
            peerId: peerId,
            body: name,
            timestamp: Date(),
            isMine: false,
            status: .delivered,
            isReadLocally: activePeerId == peerId,
            attachmentPath: path,
            attachmentName: name,
            attachmentMime: mime
        )
        append(message, to: peerId)
        return true
    }

    /// Moves an outgoing message's status forward, never backwards, so a
    /// late "delivered" ack can never downgrade "read".
    func advanceStatus(ids: [String], to newStatus: MessageStatus) {
        let order: [MessageStatus: Int] = [.pending: 0, .sent: 1, .delivered: 2, .read: 3]
        var changed = false
        for (peerId, list) in messagesByPeer {
            var updated = list
            for index in updated.indices
            where updated[index].isMine && ids.contains(updated[index].id) {
                let current = order[updated[index].status] ?? 0
                if let target = order[newStatus], target > current {
                    updated[index].status = newStatus
                    changed = true
                }
            }
            if updated != list {
                messagesByPeer[peerId] = updated
            }
        }
        if changed { save() }
    }

    /// Marks all incoming messages as seen locally; returns the ids that
    /// were unread so a read receipt can be sent to the peer.
    func markConversationSeen(peerId: String) -> [String] {
        guard var list = messagesByPeer[peerId] else { return [] }
        var newlyRead: [String] = []
        for index in list.indices where !list[index].isMine && !list[index].isReadLocally {
            list[index].isReadLocally = true
            newlyRead.append(list[index].id)
        }
        if !newlyRead.isEmpty {
            messagesByPeer[peerId] = list
            save()
        }
        return newlyRead
    }

    func deleteConversation(peerId: String) {
        conversations.removeAll { $0.peerId == peerId }
        messagesByPeer[peerId] = nil
        save()
    }

    // MARK: - Groups

    func ensureGroup(groupId: String, name: String, members: [String]) {
        if let index = conversations.firstIndex(where: { $0.peerId == groupId }) {
            if conversations[index].name != name || (conversations[index].memberIds ?? []) != members {
                conversations[index].name = name
                conversations[index].memberIds = members
                conversations[index].isGroup = true
                save()
            }
        } else {
            conversations.append(
                Conversation(
                    peerId: groupId,
                    name: name,
                    lastActivity: Date(),
                    isGroup: true,
                    memberIds: members
                )
            )
            save()
        }
    }

    func recordGroupOutgoing(groupId: String, senderName: String, body: String) -> ChatMessage {
        let message = ChatMessage(
            id: UUID().uuidString,
            peerId: groupId,
            body: body,
            timestamp: Date(),
            isMine: true,
            status: .sent,
            isReadLocally: true,
            senderName: senderName
        )
        append(message, to: groupId)
        return message
    }

    /// Records a received group message unless its id is already known.
    func recordGroupIncoming(
        msgId: String,
        groupId: String,
        senderName: String,
        body: String,
        timestamp: Date
    ) -> ChatMessage? {
        guard !messages(for: groupId).contains(where: { $0.id == msgId }) else { return nil }
        let message = ChatMessage(
            id: msgId,
            peerId: groupId,
            body: body,
            timestamp: timestamp,
            isMine: false,
            status: .delivered,
            isReadLocally: activePeerId == groupId,
            senderName: senderName
        )
        append(message, to: groupId)
        return message
    }

    private func append(_ message: ChatMessage, to peerId: String) {
        messagesByPeer[peerId, default: []].append(message)
        if let index = conversations.firstIndex(where: { $0.peerId == peerId }) {
            conversations[index].lastActivity = max(conversations[index].lastActivity, message.timestamp)
        } else {
            conversations.append(
                Conversation(peerId: peerId, name: "Unknown", lastActivity: message.timestamp)
            )
        }
        save()
    }

    // MARK: - Persistence

    private static var storeURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("bluetalk-store.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.storeURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return }
        conversations = snapshot.conversations
        messagesByPeer = snapshot.messagesByPeer
    }

    private func save() {
        let snapshot = Snapshot(conversations: conversations, messagesByPeer: messagesByPeer)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: Self.storeURL, options: .atomic)
    }
}

/// UIDevice lives in UIKit; isolate the import so the rest of the store
/// stays UI-framework free.
private enum UIDeviceName {
    static var current: String {
        #if canImport(UIKit)
        return UIKit.UIDevice.current.name
        #else
        return "BlueTalk user"
        #endif
    }
}

#if canImport(UIKit)
import UIKit
#endif
