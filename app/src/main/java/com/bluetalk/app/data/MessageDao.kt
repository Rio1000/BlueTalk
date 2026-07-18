package com.bluetalk.app.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface MessageDao {

    /** IGNORE so a peer re-sending an unacknowledged message never duplicates it. */
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insert(message: Message)

    @Query("SELECT * FROM messages WHERE conversationAddress = :address ORDER BY timestamp DESC")
    fun messagesFor(address: String): Flow<List<Message>>

    /**
     * Moves a message's status forward only if it is currently in one of the
     * expected states, so a late "delivered" ack can never downgrade "read".
     */
    @Query("UPDATE messages SET status = :new WHERE id = :id AND isMine = 1 AND status IN (:from)")
    suspend fun transition(id: String, new: MessageStatus, from: List<MessageStatus>)

    @Query("UPDATE messages SET status = :new WHERE id IN (:ids) AND isMine = 1 AND status IN (:from)")
    suspend fun transitionAll(ids: List<String>, new: MessageStatus, from: List<MessageStatus>)

    @Query(
        """
        SELECT * FROM messages WHERE conversationAddress = :address
            AND isMine = 1 AND status = :status ORDER BY timestamp ASC
        """
    )
    suspend fun outgoingWithStatus(address: String, status: MessageStatus): List<Message>

    @Query("SELECT id FROM messages WHERE conversationAddress = :address AND isMine = 0 AND isRead = 0")
    suspend fun unreadIncomingIds(address: String): List<String>

    @Query("UPDATE messages SET isRead = 1 WHERE conversationAddress = :address AND isMine = 0")
    suspend fun markIncomingRead(address: String)

    @Query("DELETE FROM messages WHERE conversationAddress = :address")
    suspend fun deleteFor(address: String)
}
