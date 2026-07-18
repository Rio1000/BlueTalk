package com.bluetalk.app.data

import kotlinx.coroutines.flow.Flow

class ChatRepository(
    private val conversationDao: ConversationDao,
    private val messageDao: MessageDao,
) {

    fun summaries(): Flow<List<ConversationSummary>> = conversationDao.summaries()

    fun messagesFor(address: String): Flow<List<Message>> = messageDao.messagesFor(address)

    fun conversationName(address: String): Flow<String?> = conversationDao.nameFor(address)

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
}
