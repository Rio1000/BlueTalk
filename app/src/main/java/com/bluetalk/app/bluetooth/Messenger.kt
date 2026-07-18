package com.bluetalk.app.bluetooth

import android.net.Uri
import com.bluetalk.app.bluetooth.ble.BleConnectionManager
import com.bluetalk.app.data.Message
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.flow.stateIn

/**
 * Single entry point the UI talks to, hiding the fact that BlueTalk speaks
 * two Bluetooth transports at once. Each conversation is owned by exactly
 * one transport, decided by its address: Bluetooth Classic conversations
 * are keyed by MAC address (which always contains ':'), BLE conversations
 * by an install-stable peer id (a UUID, which never does).
 */
class Messenger(
    scope: CoroutineScope,
    private val rfcomm: ConnectionManager,
    private val ble: BleConnectionManager,
) {

    val peerStates: StateFlow<Map<String, PeerState>> =
        combine(rfcomm.peerStates, ble.peerStates) { a, b -> a + b }
            .stateIn(scope, SharingStarted.Eagerly, emptyMap())

    val typingPeers: StateFlow<Set<String>> =
        combine(rfcomm.typingPeers, ble.typingPeers) { a, b -> a + b }
            .stateIn(scope, SharingStarted.Eagerly, emptySet())

    val incoming: Flow<Message> = merge(rfcomm.incoming, ble.incoming)

    var activeConversation: String? = null
        set(value) {
            field = value
            rfcomm.activeConversation = value
            ble.activeConversation = value
        }

    fun startServers() {
        rfcomm.startServer()
        ble.startServer()
    }

    fun isBluetoothEnabled(): Boolean = rfcomm.isBluetoothEnabled()

    fun connect(address: String) = transportFor(address).connect(address)

    fun sendMessage(address: String, body: String) = transportFor(address).sendMessage(address, body)

    fun sendAttachment(address: String, uri: Uri) = transportFor(address).sendAttachment(address, uri)

    fun sendTyping(address: String, active: Boolean) =
        transportFor(address).sendTyping(address, active)

    fun markConversationSeen(address: String) = transportFor(address).markConversationSeen(address)

    /** Bluetooth MAC addresses contain ':'; BLE peer ids (UUIDs) do not. */
    private fun transportFor(address: String): MessageTransport =
        if (address.contains(':')) rfcomm else ble
}
