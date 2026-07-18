import Foundation

/// Ties the two BLE controllers to the chat logic: sends `hello` on new
/// links, routes frames into the store, acknowledges messages, flushes the
/// pending queue when a peer (re)connects and fans typing/read events out
/// to the right link.
///
/// Runs entirely on the main thread — both controllers deliver their
/// callbacks there and the UI calls in from SwiftUI.
final class BluetoothManager: NSObject, ObservableObject {

    @Published private(set) var discovered: [DiscoveredPeer] = []
    @Published private(set) var scanning = false
    /// Peer ids with at least one live link.
    @Published private(set) var connectedPeerIds: Set<String> = []
    /// Discovered-device ids we are currently trying to connect to.
    @Published private(set) var connecting: Set<UUID> = []

    private struct Link {
        let send: (Data) -> Void
        let close: () -> Void
        var peerId: String?
    }

    private let store: ChatStore
    private let fileTransfer = FileTransfer()
    private var central: CentralController!
    private var peripheral: PeripheralController!
    private var links: [UUID: Link] = [:]
    private var reconnectTimers: [UUID: DispatchWorkItem] = [:]

    private static let maxSeenEntries = 500
    private var seenGroupMessages: [String] = []
    private var seenGroupInvites: [String] = []
    private var seenGroupMessageSet = Set<String>()
    private var seenGroupInviteSet = Set<String>()

    init(store: ChatStore) {
        self.store = store
        super.init()
        central = CentralController(
            onDiscovery: { [weak self] peer in self?.noteDiscovery(peer) },
            onScanState: { [weak self] active in self?.scanning = active }
        )
        central.delegate = self
        peripheral = PeripheralController(localName: store.displayName)
        peripheral.delegate = self
    }

    // MARK: - UI entry points

    func startScan() {
        discovered.removeAll()
        central.startScan()
    }

    func stopScan() {
        central.stopScan()
    }

    func connect(to discoveredId: UUID) {
        connecting.insert(discoveredId)
        central.connect(to: discoveredId)
    }

    func sendMessage(peerId: String, body: String) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.ensureConversation(peerId: peerId, name: nil)
        _ = store.recordOutgoing(peerId: peerId, body: trimmed)
        flushPending(peerId: peerId)
    }

    func sendAttachment(peerId: String, url: URL) {
        guard let attachment = fileTransfer.importOutgoing(from: url) else { return }
        store.ensureConversation(peerId: peerId, name: nil)
        _ = store.recordOutgoingAttachment(
            peerId: peerId,
            path: attachment.path,
            name: attachment.name,
            mime: attachment.mime
        )
        flushPending(peerId: peerId)
    }

    func sendTyping(peerId: String, active: Bool) {
        guard let link = link(for: peerId) else { return }
        link.send(Frame.typing(active: active).encoded())
    }

    /// Creates a group, stores it, and announces it to members. Returns its id.
    func createGroup(name: String, memberPeerIds: [String]) -> String {
        let groupId = UUID().uuidString
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let groupName = trimmed.isEmpty ? "Group" : trimmed
        let members = Array(Set(memberPeerIds + [store.myPeerId]))
        store.ensureGroup(groupId: groupId, name: groupName, members: members)
        broadcast(.groupInvite(groupId: groupId, name: groupName, members: members, from: store.displayName), except: nil)
        return groupId
    }

    func sendGroupMessage(groupId: String, body: String) {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let members = store.groupMembers(groupId)
        let name = store.conversationName(for: groupId)
        let msgId = UUID().uuidString
        insertSeen(id: msgId, into: &seenGroupMessages, set: &seenGroupMessageSet)
        _ = store.recordGroupOutgoing(groupId: groupId, senderName: store.displayName, body: text)
        let millis = Int64(Date().timeIntervalSince1970 * 1000)
        broadcast(
            .groupText(
                groupId: groupId, name: name, members: members, msgId: msgId,
                senderId: store.myPeerId, senderName: store.displayName, body: text,
                timestampMillis: millis
            ),
            except: nil
        )
    }

    /// Floods a frame to every connected peer except the one it came from.
    private func broadcast(_ frame: Frame, except linkId: UUID?) {
        let data = frame.encoded()
        for (id, link) in links where id != linkId {
            link.send(data)
        }
    }

    /// Marks the conversation read locally and sends the peer a receipt.
    func markConversationSeen(peerId: String) {
        let ids = store.markConversationSeen(peerId: peerId)
        if !ids.isEmpty, let link = link(for: peerId) {
            link.send(Frame.read(ids: ids).encoded())
        }
    }

    func displayNameChanged(_ name: String) {
        peripheral.updateLocalName(name)
    }

    // MARK: - Frame handling

    private func handle(_ frame: Frame, linkId: UUID) {
        switch frame {
        case .hello(let name, let peerId):
            guard !peerId.isEmpty else { return }
            links[linkId]?.peerId = peerId
            store.ensureConversation(peerId: peerId, name: name)
            connectedPeerIds.insert(peerId)
            flushPending(peerId: peerId)

        case .text(let id, let body, _):
            guard let peerId = links[linkId]?.peerId else { return }
            let isNew = store.recordIncoming(id: id, peerId: peerId, body: body)
            links[linkId]?.send(Frame.delivered(id: id).encoded())
            if store.activePeerId == peerId {
                links[linkId]?.send(Frame.read(ids: [id]).encoded())
                if isNew {
                    _ = store.markConversationSeen(peerId: peerId)
                }
            } else if isNew {
                LocalNotifications.post(
                    title: store.conversationName(for: peerId),
                    body: body,
                    threadId: peerId
                )
            }

        case .delivered(let id):
            store.advanceStatus(ids: [id], to: .delivered)

        case .read(let ids):
            store.advanceStatus(ids: ids, to: .read)

        case .typing(let active):
            guard let peerId = links[linkId]?.peerId else { return }
            if active {
                store.typingPeers.insert(peerId)
            } else {
                store.typingPeers.remove(peerId)
            }

        case .fileStart(let id, let name, let mime, _):
            fileTransfer.startIncoming(id: id, name: name, mime: mime)

        case .fileData(let id, _, let data):
            fileTransfer.appendIncoming(id: id, base64: data)

        case .fileEnd(let id):
            guard let peerId = links[linkId]?.peerId,
                  let attachment = fileTransfer.finishIncoming(id: id) else { return }
            let isNew = store.recordIncomingAttachment(
                id: id,
                peerId: peerId,
                path: attachment.path,
                name: attachment.name,
                mime: attachment.mime
            )
            links[linkId]?.send(Frame.delivered(id: id).encoded())
            if store.activePeerId == peerId {
                links[linkId]?.send(Frame.read(ids: [id]).encoded())
                if isNew {
                    _ = store.markConversationSeen(peerId: peerId)
                }
            } else if isNew {
                LocalNotifications.post(
                    title: store.conversationName(for: peerId),
                    body: "📎 \(attachment.name)",
                    threadId: peerId
                )
            }

        case .groupInvite(let groupId, let name, let members, _):
            if seenGroupInviteSet.contains(groupId) { return }
            insertSeen(id: groupId, into: &seenGroupInvites, set: &seenGroupInviteSet)
            if members.contains(store.myPeerId) {
                store.ensureGroup(groupId: groupId, name: name, members: members)
            }
            broadcast(frame, except: linkId)

        case .groupText(let groupId, let name, let members, let msgId, let senderId, let senderName, let body, let ts):
            if seenGroupMessageSet.contains(msgId) { return }
            insertSeen(id: msgId, into: &seenGroupMessages, set: &seenGroupMessageSet)
            if members.contains(store.myPeerId), senderId != store.myPeerId {
                store.ensureGroup(groupId: groupId, name: name, members: members)
                let timestamp = Date(timeIntervalSince1970: TimeInterval(ts) / 1000)
                let onScreen = store.activePeerId == groupId
                if store.recordGroupIncoming(
                    msgId: msgId, groupId: groupId, senderName: senderName,
                    body: body, timestamp: timestamp
                ) != nil, !onScreen {
                    LocalNotifications.post(title: name, body: "\(senderName): \(body)", threadId: groupId)
                }
            }
            // Relay onward so members reachable only through us still receive it.
            broadcast(frame, except: linkId)
        }
    }

    /// Sends every queued message for the peer in order, oldest first.
    private func flushPending(peerId: String) {
        guard let link = link(for: peerId) else { return }
        for message in store.pendingMessages(for: peerId) {
            if let path = message.attachmentPath {
                fileTransfer.sendFile(
                    path: path,
                    name: message.attachmentName ?? "file",
                    mime: message.attachmentMime ?? "application/octet-stream",
                    id: message.id
                ) { frame in
                    link.send(frame.encoded())
                }
            } else {
                let millis = Int64(message.timestamp.timeIntervalSince1970 * 1000)
                link.send(Frame.text(id: message.id, body: message.body, timestampMillis: millis).encoded())
            }
            store.advanceStatus(ids: [message.id], to: .sent)
        }
    }

    private func link(for peerId: String) -> Link? {
        links.values.first(where: { $0.peerId == peerId })
    }

    private func noteDiscovery(_ peer: DiscoveredPeer) {
        if let index = discovered.firstIndex(where: { $0.id == peer.id }) {
            discovered[index] = peer
        } else {
            discovered.append(peer)
        }
    }

    private func insertSeen(id: String, into list: inout [String], set: inout Set<String>) {
        set.insert(id)
        list.append(id)
        if list.count > Self.maxSeenEntries {
            let excess = list.count - Self.maxSeenEntries
            let evicted = list.prefix(excess)
            for item in evicted { set.remove(item) }
            list.removeFirst(excess)
        }
    }
}

extension BluetoothManager: LinkEventDelegate {

    func linkUp(linkId: UUID, send: @escaping (Data) -> Void, close: @escaping () -> Void) {
        links[linkId] = Link(send: send, close: close, peerId: nil)
        connecting.remove(linkId)
        send(Frame.hello(name: store.displayName, peerId: store.myPeerId).encoded())
    }

    func linkDown(linkId: UUID) {
        guard let link = links.removeValue(forKey: linkId) else { return }
        connecting.remove(linkId)
        if let peerId = link.peerId, self.link(for: peerId) == nil {
            connectedPeerIds.remove(peerId)
            store.typingPeers.remove(peerId)
            scheduleReconnect(linkId: linkId)
        }
    }

    private func scheduleReconnect(linkId: UUID) {
        reconnectTimers[linkId]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.reconnectTimers[linkId] = nil
            self?.central.connect(to: linkId)
        }
        reconnectTimers[linkId] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    func frameReceived(linkId: UUID, frame data: Data) {
        guard let frame = Frame.decode(data) else { return }
        handle(frame, linkId: linkId)
    }
}
