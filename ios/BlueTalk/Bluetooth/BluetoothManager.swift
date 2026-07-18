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
        }
    }

    func frameReceived(linkId: UUID, frame data: Data) {
        guard let frame = Frame.decode(data) else { return }
        handle(frame, linkId: linkId)
    }
}
