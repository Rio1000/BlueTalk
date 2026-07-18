package com.bluetalk.app.bluetooth

import com.bluetalk.app.data.Message
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * A way to exchange BlueTalk messages with peers. Implemented once for
 * Bluetooth Classic (RFCOMM, [ConnectionManager]) and once for Bluetooth
 * Low Energy ([com.bluetalk.app.bluetooth.ble.BleConnectionManager]).
 *
 * Conversations are addressed by a transport-specific key: a MAC address
 * for RFCOMM, an install-stable peer id for BLE. The two key spaces never
 * overlap (MACs contain ':'; peer ids are UUIDs), which is how [Messenger]
 * decides who owns a conversation.
 */
interface MessageTransport {

    /** Connection state per conversation key. */
    val peerStates: StateFlow<Map<String, PeerState>>

    /** Conversation keys whose peer is currently typing. */
    val typingPeers: StateFlow<Set<String>>

    /** Messages that arrived while their conversation was off screen. */
    val incoming: SharedFlow<Message>

    /** Conversation currently on screen; its incoming messages are auto-read. */
    var activeConversation: String?

    /** Starts accepting inbound connections. */
    fun startServer()

    /** (Re)establishes a link to the given conversation key. */
    fun connect(address: String)

    fun sendMessage(address: String, body: String)

    fun sendTyping(address: String, active: Boolean)

    fun markConversationSeen(address: String)
}
