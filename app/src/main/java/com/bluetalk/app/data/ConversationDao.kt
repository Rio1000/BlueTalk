package com.bluetalk.app.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface ConversationDao {

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(conversation: Conversation)

    @Query("SELECT * FROM conversations WHERE address = :address")
    suspend fun get(address: String): Conversation?

    @Query("SELECT name FROM conversations WHERE address = :address")
    fun nameFor(address: String): Flow<String?>

    @Query("SELECT isGroup FROM conversations WHERE address = :address")
    fun isGroupFlow(address: String): Flow<Boolean?>

    @Query("UPDATE conversations SET name = :name WHERE address = :address")
    suspend fun rename(address: String, name: String)

    @Query("UPDATE conversations SET lastActivity = MAX(lastActivity, :at) WHERE address = :address")
    suspend fun touch(address: String, at: Long)

    @Query("UPDATE conversations SET peerId = :peerId WHERE address = :address")
    suspend fun setPeerId(address: String, peerId: String)

    /** 1:1 contacts whose stable peer id is known, for the group member picker. */
    @Query("SELECT * FROM conversations WHERE isGroup = 0 AND peerId IS NOT NULL ORDER BY name")
    suspend fun contactsWithPeerId(): List<Conversation>

    @Query(
        """
        SELECT c.address AS address,
               c.name AS name,
               c.lastActivity AS lastActivity,
               c.isGroup AS isGroup,
               (SELECT m.body FROM messages m WHERE m.conversationAddress = c.address
                    ORDER BY m.timestamp DESC LIMIT 1) AS lastMessage,
               (SELECT m.isMine FROM messages m WHERE m.conversationAddress = c.address
                    ORDER BY m.timestamp DESC LIMIT 1) AS lastMessageIsMine,
               (SELECT COUNT(*) FROM messages m WHERE m.conversationAddress = c.address
                    AND m.isMine = 0 AND m.isRead = 0) AS unreadCount
        FROM conversations c
        ORDER BY c.lastActivity DESC
        """
    )
    fun summaries(): Flow<List<ConversationSummary>>

    @Query("DELETE FROM conversations WHERE address = :address")
    suspend fun delete(address: String)
}
