package com.bluetalk.app.data

import kotlinx.coroutines.flow.Flow
import org.json.JSONArray
import java.util.UUID

class ChatRepository(
    private val conversationDao: ConversationDao,
    private val messageDao: MessageDao,
) {

    fun summaries(): Flow<List<ConversationSummary>> = conversationDao.summaries()

    fun messagesFor(address: String): Flow<List<Message>> = messageDao.messagesFor(address)

    fun conversationName(address: String): Flow<String?> = conversationDao.nameFor(address)

    fun conversationIsGroup(address: String): Flow<Boolean?> = conversationDao.isGroupFlow(address)

    suspend fun displayName(address: String): String =
        conversationDao.get(address)?.name ?: address

    /**
     * Creates the conversation if missing. A non-null [name] also refreshes
     * the stored name (peers announce theirs in the hello frame).
     */
    suspend fun ensureConversation(address: String, name: String?) {
        val existing = conversationDao.get(address)
        when {
            existing == null ->
                conversationDao.upsert(Conversation(address, name ?: address, System.currentTimeMillis()))
            name != null && name.isNotBlank() && name != existing.name ->
                conversationDao.rename(address, name)
        }
    }

    suspend fun recordOutgoing(message: Message) {
        messageDao.insert(message)
        conversationDao.touch(message.conversationAddress, message.timestamp)
    }

    suspend fun recordIncoming(message: Message) {
        messageDao.insert(message)
        conversationDao.touch(message.conversationAddress, message.timestamp)
    }

    suspend fun pendingFor(address: String): List<Message> =
        messageDao.outgoingWithStatus(address, MessageStatus.PENDING)

    suspend fun markSent(id: String) =
        messageDao.transition(id, MessageStatus.SENT, listOf(MessageStatus.PENDING))

    suspend fun markDelivered(id: String) =
        messageDao.transition(id, MessageStatus.DELIVERED, listOf(MessageStatus.PENDING, MessageStatus.SENT))

    suspend fun markRead(ids: List<String>) = messageDao.transitionAll(
        ids,
        MessageStatus.READ,
        listOf(MessageStatus.PENDING, MessageStatus.SENT, MessageStatus.DELIVERED),
    )

    /** Marks all incoming messages as seen locally and returns the ids that were unread. */
    suspend fun markConversationSeen(address: String): List<String> {
        val ids = messageDao.unreadIncomingIds(address)
        if (ids.isNotEmpty()) messageDao.markIncomingRead(address)
        return ids
    }

    suspend fun deleteConversation(address: String) {
        messageDao.deleteFor(address)
        conversationDao.delete(address)
    }

    // ---- Groups ------------------------------------------------------

    suspend fun getConversation(address: String): Conversation? = conversationDao.get(address)

    /** Records the remote peer's stable id on a 1:1 conversation. */
    suspend fun setPeerId(address: String, peerId: String) {
        if (peerId.isBlank()) return
        val existing = conversationDao.get(address)
        if (existing != null && existing.peerId != peerId) {
            conversationDao.setPeerId(address, peerId)
        }
    }

    /** 1:1 contacts whose stable peer id is known, for the group member picker. */
    suspend fun contactsWithPeerId(): List<Conversation> = conversationDao.contactsWithPeerId()

    /** Creates a group conversation if missing, or refreshes its name/members. */
    suspend fun ensureGroup(groupId: String, name: String, members: List<String>) {
        val existing = conversationDao.get(groupId)
        val encoded = JSONArray(members).toString()
        if (existing == null) {
            conversationDao.upsert(
                Conversation(
                    address = groupId,
                    name = name,
                    lastActivity = System.currentTimeMillis(),
                    isGroup = true,
                    memberIds = encoded,
                    peerId = null,
                )
            )
        } else if (existing.name != name || existing.memberIds != encoded) {
            conversationDao.upsert(existing.copy(name = name, memberIds = encoded, isGroup = true))
        }
    }

    suspend fun groupMembers(groupId: String): List<String> {
        val encoded = conversationDao.get(groupId)?.memberIds ?: return emptyList()
        val array = JSONArray(encoded)
        return List(array.length()) { array.getString(it) }
    }

    /** Stores an outgoing group message (broadcast, so marked sent immediately). */
    suspend fun recordGroupOutgoing(msgId: String, groupId: String, senderName: String, body: String): Message {
        val message = Message(
            id = msgId,
            conversationAddress = groupId,
            body = body,
            timestamp = System.currentTimeMillis(),
            isMine = true,
            status = MessageStatus.SENT,
            isRead = true,
            senderName = senderName,
        )
        messageDao.insert(message)
        conversationDao.touch(groupId, message.timestamp)
        return message
    }

    /** Stores a received group message. Returns the stored row for notifications. */
    suspend fun recordGroupIncoming(
        msgId: String,
        groupId: String,
        senderName: String,
        body: String,
        timestamp: Long,
        seen: Boolean,
    ): Message {
        val message = Message(
            id = msgId,
            conversationAddress = groupId,
            body = body,
            timestamp = timestamp,
            isMine = false,
            status = MessageStatus.DELIVERED,
            isRead = seen,
            senderName = senderName,
        )
        messageDao.insert(message)
        conversationDao.touch(groupId, timestamp)
        return message
    }

    fun newGroupId(): String = UUID.randomUUID().toString()
}
