package com.bluetalk.app.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bluetalk.app.AppContainer
import com.bluetalk.app.bluetooth.ConnectionStatus
import com.bluetalk.app.bluetooth.DeviceDiscovery
import com.bluetalk.app.bluetooth.PeerState
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

    val peerStates: StateFlow<Map<String, PeerState>> = container.connectionManager.peerStates
}

class ChatViewModel(
    private val container: AppContainer,
    val address: String,
) : ViewModel() {

    private val connectionManager = container.connectionManager

    val messages: StateFlow<List<Message>> = container.repository.messagesFor(address)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val title: StateFlow<String> = container.repository.conversationName(address)
        .map { it ?: address }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), address)

    val peerState: StateFlow<PeerState> = connectionManager.peerStates
        .map { it[address] ?: PeerState(ConnectionStatus.DISCONNECTED) }
        .stateIn(
            viewModelScope,
            SharingStarted.WhileSubscribed(5_000),
            PeerState(ConnectionStatus.DISCONNECTED),
        )

    val peerTyping: StateFlow<Boolean> = connectionManager.typingPeers
        .map { address in it }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), false)

    private var typingJob: Job? = null
    private var typingSent = false

    /** Called when the conversation comes on screen. */
    fun onOpen() {
        connectionManager.activeConversation = address
        connectionManager.markConversationSeen(address)
        connectionManager.connect(address)
    }

    /** Called when the conversation leaves the screen. */
    fun onClose() {
        if (connectionManager.activeConversation == address) {
            connectionManager.activeConversation = null
        }
        stopTyping()
    }

    fun send(body: String) {
        stopTyping()
        connectionManager.sendMessage(address, body)
    }

    fun connect() {
        connectionManager.connect(address)
    }

    /** Debounced typing indicator: fires once, clears after a pause. */
    fun onDraftChanged(draft: String) {
        if (draft.isEmpty()) {
            stopTyping()
            return
        }
        if (!typingSent) {
            typingSent = true
            connectionManager.sendTyping(address, true)
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
            connectionManager.sendTyping(address, false)
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

    val scanning: StateFlow<Boolean> = discovery.scanning
    val found: StateFlow<List<DeviceDiscovery.Device>> = discovery.found

    private val _paired = MutableStateFlow<List<DeviceDiscovery.Device>>(emptyList())
    val paired: StateFlow<List<DeviceDiscovery.Device>> = _paired

    fun refreshPaired() {
        _paired.value = discovery.pairedDevices()
    }

    fun startScan() = discovery.startScan()

    fun stopScan() = discovery.stopScan()

    /** Creates the conversation, kicks off a connection and hands back to navigation. */
    fun openChat(device: DeviceDiscovery.Device, onReady: () -> Unit) {
        viewModelScope.launch {
            container.repository.ensureConversation(device.address, device.name)
            container.connectionManager.connect(device.address)
            onReady()
        }
    }

    override fun onCleared() {
        discovery.stopScan()
    }
}
