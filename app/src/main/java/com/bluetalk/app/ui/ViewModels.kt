package com.bluetalk.app.ui

import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bluetalk.app.AppContainer
import com.bluetalk.app.bluetooth.ConnectionStatus
import com.bluetalk.app.bluetooth.DeviceDiscovery
import com.bluetalk.app.bluetooth.PeerState
import com.bluetalk.app.bluetooth.ble.BleDevice
import com.bluetalk.app.data.ConversationSummary
import com.bluetalk.app.data.Message
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class ConversationsViewModel(container: AppContainer) : ViewModel() {

    val summaries: StateFlow<List<ConversationSummary>> = container.repository.summaries()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val peerStates: StateFlow<Map<String, PeerState>> = container.messenger.peerStates
}

class ChatViewModel(
    private val container: AppContainer,
    val address: String,
) : ViewModel() {

    private val messenger = container.messenger

    val messages: StateFlow<List<Message>> = container.repository.messagesFor(address)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val title: StateFlow<String> = container.repository.conversationName(address)
        .map { it ?: address }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), address)

    val peerState: StateFlow<PeerState> = messenger.peerStates
        .map { it[address] ?: PeerState(ConnectionStatus.DISCONNECTED) }
        .stateIn(
            viewModelScope,
            SharingStarted.WhileSubscribed(5_000),
            PeerState(ConnectionStatus.DISCONNECTED),
        )

    val peerTyping: StateFlow<Boolean> = messenger.typingPeers
        .map { address in it }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), false)

    private var typingJob: Job? = null
    private var typingSent = false

    /** Called when the conversation comes on screen. */
    fun onOpen() {
        messenger.activeConversation = address
        messenger.markConversationSeen(address)
        messenger.connect(address)
    }

    /** Called when the conversation leaves the screen. */
    fun onClose() {
        if (messenger.activeConversation == address) {
            messenger.activeConversation = null
        }
        stopTyping()
    }

    fun send(body: String) {
        stopTyping()
        messenger.sendMessage(address, body)
    }

    fun sendAttachment(uri: Uri) {
        messenger.sendAttachment(address, uri)
    }

    fun connect() {
        messenger.connect(address)
    }

    /** Debounced typing indicator: fires once, clears after a pause. */
    fun onDraftChanged(draft: String) {
        if (draft.isEmpty()) {
            stopTyping()
            return
        }
        if (!typingSent) {
            typingSent = true
            messenger.sendTyping(address, true)
        }
        typingJob?.cancel()
        typingJob = viewModelScope.launch {
            delay(TYPING_TIMEOUT_MS)
            stopTyping()
        }
    }

    private fun stopTyping() {
        typingJob?.cancel()
        typingJob = null
        if (typingSent) {
            typingSent = false
            messenger.sendTyping(address, false)
        }
    }

    override fun onCleared() {
        onClose()
    }

    companion object {
        private const val TYPING_TIMEOUT_MS = 3_000L
    }
}

class DiscoverViewModel(private val container: AppContainer) : ViewModel() {

    private val discovery = container.discovery
    private val ble = container.bleManager

    // Bluetooth Classic (Android <-> Android).
    val scanning: StateFlow<Boolean> = discovery.scanning
    val found: StateFlow<List<DeviceDiscovery.Device>> = discovery.found

    private val _paired = MutableStateFlow<List<DeviceDiscovery.Device>>(emptyList())
    val paired: StateFlow<List<DeviceDiscovery.Device>> = _paired

    // Bluetooth Low Energy (Android <-> iPhone and Android <-> Android).
    val bleScanning: StateFlow<Boolean> = ble.scanning
    val bleDevices: StateFlow<List<BleDevice>> = ble.discovered

    fun refreshPaired() {
        _paired.value = discovery.pairedDevices()
    }

    fun startScan() {
        discovery.startScan()
        ble.startScan()
    }

    fun stopScan() {
        discovery.stopScan()
        ble.stopScan()
    }

    /** Opens (or starts) an RFCOMM chat with a classic/paired device. */
    fun openChat(device: DeviceDiscovery.Device, onReady: () -> Unit) {
        viewModelScope.launch {
            container.repository.ensureConversation(device.address, device.name)
            container.messenger.connect(device.address)
            onReady()
        }
    }

    /**
     * Connects to a nearby BLE device. The conversation is keyed by the
     * peer id we learn from its hello frame, so it appears in the list once
     * the link is up rather than immediately.
     */
    fun connectBle(device: BleDevice) {
        ble.connectDevice(device.address)
    }

    override fun onCleared() {
        discovery.stopScan()
        ble.stopScan()
    }
}
