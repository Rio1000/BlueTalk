package com.bluetalk.app.bluetooth

import com.bluetalk.app.data.ChatRepository
import com.bluetalk.app.data.Message
import com.bluetalk.app.settings.SettingsStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.launch
import java.util.Collections

/**
 * Serverless group chat over a gossip mesh. A group message is flooded to
 * every connected peer; members store and display it, and everyone
 * re-broadcasts messages they haven't seen so members reach each other
 * through mutual peers even without a direct link. Message ids de-dupe
 * relays (bounded seen-set) and storage (INSERT IGNORE), which also breaks
 * flood loops.
 *
 * Membership travels inside every frame, so a member who missed the invite
 * still joins on the first message it relays. Groups are keyed by a random
 * id; members are identified by their install-stable peer id.
 */
class GroupManager(
    private val repository: ChatRepository,
    private val settings: SettingsStore,
    private val messenger: Messenger,
    private val scope: CoroutineScope,
) {

    private val _incoming = MutableSharedFlow<Message>(extraBufferCapacity = 32)

    /** Group messages that arrived while their group was off screen. */
    val incoming: SharedFlow<Message> = _incoming.asSharedFlow()

    private val seenMessages = Collections.synchronizedSet(LinkedHashSet<String>())
    private val seenInvites = Collections.synchronizedSet(HashSet<String>())

    /** Creates a group, stores it locally, and announces it to members. */
    fun createGroup(name: String, memberPeerIds: List<String>): String {
        val groupId = repository.newGroupId()
        val groupName = name.trim().ifEmpty { "Group" }
        val members = (memberPeerIds + settings.peerId).distinct()
        scope.launch {
            repository.ensureGroup(groupId, groupName, members)
            messenger.broadcast(
                Frame.GroupInvite(groupId, groupName, members, settings.displayName.value),
                exceptAddress = null,
            )
        }
        return groupId
    }

    fun sendGroupMessage(groupId: String, body: String) {
        val text = body.trim()
        if (text.isEmpty()) return
        scope.launch {
            val group = repository.getConversation(groupId) ?: return@launch
            val members = repository.groupMembers(groupId)
            val msgId = repository.newGroupId()
            rememberSeen(msgId)
            repository.recordGroupOutgoing(msgId, groupId, settings.displayName.value, text)
            messenger.broadcast(
                Frame.GroupText(
                    groupId = groupId,
                    name = group.name,
                    members = members,
                    msgId = msgId,
                    senderId = settings.peerId,
                    senderName = settings.displayName.value,
                    body = text,
                    timestamp = System.currentTimeMillis(),
                ),
                exceptAddress = null,
            )
        }
    }

    fun onGroupFrame(fromAddress: String, frame: Frame) {
        when (frame) {
            is Frame.GroupInvite -> handleInvite(fromAddress, frame)
            is Frame.GroupText -> handleText(fromAddress, frame)
            else -> {}
        }
    }

    private fun handleInvite(from: String, invite: Frame.GroupInvite) {
        if (!seenInvites.add(invite.groupId)) return
        scope.launch {
            if (settings.peerId in invite.members) {
                repository.ensureGroup(invite.groupId, invite.name, invite.members)
            }
            messenger.broadcast(invite, exceptAddress = from)
        }
    }

    private fun handleText(from: String, msg: Frame.GroupText) {
        if (!rememberSeen(msg.msgId)) return
        scope.launch {
            if (settings.peerId in msg.members && msg.senderId != settings.peerId) {
                repository.ensureGroup(msg.groupId, msg.name, msg.members)
                val onScreen = messenger.activeConversation == msg.groupId
                val message = repository.recordGroupIncoming(
                    msg.msgId, msg.groupId, msg.senderName, msg.body, msg.timestamp, onScreen,
                )
                if (!onScreen) _incoming.tryEmit(message)
            }
            // Relay onward so members reachable only through us still receive it.
            messenger.broadcast(msg, exceptAddress = from)
        }
    }

    /** Records an id as seen; returns false if it was already known. Bounded LRU. */
    private fun rememberSeen(id: String): Boolean {
        synchronized(seenMessages) {
            if (!seenMessages.add(id)) return false
            if (seenMessages.size > MAX_SEEN) {
                val iterator = seenMessages.iterator()
                iterator.next()
                iterator.remove()
            }
            return true
        }
    }

    companion object {
        private const val MAX_SEEN = 500
    }
}
