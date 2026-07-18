import Foundation

/// Delivery lifecycle of an outgoing message, mirroring the Android app:
/// pending (queued, peer unreachable), sent (written to the link),
/// delivered (acknowledged by the peer's device), read (peer saw it).
enum MessageStatus: String, Codable {
    case pending, sent, delivered, read
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: String
    let peerId: String
    let body: String
    let timestamp: Date
    let isMine: Bool
    var status: MessageStatus
    /// Whether the local user has seen this incoming message (unread badge).
    var isReadLocally: Bool
}

/// One chat per remote install, keyed by the peer id announced in `hello`.
struct Conversation: Identifiable, Codable, Equatable {
    let peerId: String
    var name: String
    var lastActivity: Date

    var id: String { peerId }
}
