package com.bluetalk.app.bluetooth

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.net.Uri
import com.bluetalk.app.data.ChatRepository
import com.bluetalk.app.data.Message
import com.bluetalk.app.data.MessageStatus
import com.bluetalk.app.settings.SettingsStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.BufferedOutputStream
import java.io.Closeable
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException
import java.util.UUID

enum class ConnectionStatus { DISCONNECTED, CONNECTING, CONNECTED }

data class PeerState(
    val status: ConnectionStatus,
    val peerName: String? = null,
)

/**
 * Owns every Bluetooth link: an RFCOMM server socket accepting inbound
 * connections plus one outbound connection per peer. Incoming frames are
 * translated into repository updates (messages, delivery ticks, read
 * receipts) and outgoing messages are queued in the database until the
 * peer is reachable.
 *
 * Runtime Bluetooth permissions are checked in the UI before any of these
 * entry points are reached; every adapter call is additionally wrapped so
 * a revoked permission degrades to a disconnect instead of a crash.
 */
@SuppressLint("MissingPermission")
class ConnectionManager(
    context: Context,
    private val repository: ChatRepository,
    private val settings: SettingsStore,
    private val scope: CoroutineScope,
) : MessageTransport {

    private val appContext = context.applicationContext
    private val bluetoothManager =
        appContext.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager

    val adapter: BluetoothAdapter?
        get() = bluetoothManager.adapter

    private val fileTransfer = FileTransfer(appContext)

    private val lock = Any()
    private val connections = mutableMapOf<String, Connection>()
    private var serverSocket: BluetoothServerSocket? = null
    private var serverJob: Job? = null

    private val _peerStates = MutableStateFlow<Map<String, PeerState>>(emptyMap())
    override val peerStates: StateFlow<Map<String, PeerState>> = _peerStates.asStateFlow()

    private val _typingPeers = MutableStateFlow<Set<String>>(emptySet())
    override val typingPeers: StateFlow<Set<String>> = _typingPeers.asStateFlow()

    private val _incoming = MutableSharedFlow<Message>(extraBufferCapacity = 32)

    /** Messages that arrived while their conversation was not on screen (for notifications). */
    override val incoming: SharedFlow<Message> = _incoming.asSharedFlow()

    /** Conversation currently on screen; its incoming messages are auto-read. */
    @Volatile
    override var activeConversation: String? = null

    override var onGroupFrame: ((String, Frame) -> Unit)? = null

    fun isBluetoothEnabled(): Boolean = try {
        adapter?.isEnabled == true
    } catch (e: SecurityException) {
        false
    }

    // ------------------------------------------------------------------
    // Server (inbound connections)
    // ------------------------------------------------------------------

    override fun startServer() {
        synchronized(lock) {
            if (serverJob?.isActive == true) return
            serverJob = scope.launch(Dispatchers.IO) { runServer() }
        }
    }

    private suspend fun runServer() {
        while (currentCoroutineContext().isActive) {
            val bluetooth = adapter
            if (bluetooth == null || !isBluetoothEnabled()) {
                delay(RETRY_DELAY_MS)
                continue
            }
            val server = try {
                bluetooth.listenUsingRfcommWithServiceRecord(SDP_SERVICE_NAME, SERVICE_UUID)
            } catch (e: IOException) {
                delay(RETRY_DELAY_MS)
                continue
            } catch (e: SecurityException) {
                delay(RETRY_DELAY_MS)
                continue
            }
            synchronized(lock) { serverSocket = server }
            try {
                while (true) {
                    val socket = server.accept()
                    onSocketConnected(socket)
                }
            } catch (e: IOException) {
                // Listen socket closed (Bluetooth toggled off or shutdown); retry while active.
            } finally {
                closeQuietly(server)
                synchronized(lock) { if (serverSocket === server) serverSocket = null }
            }
        }
    }

    /** Stops listening and drops every open connection. */
    fun shutdown() {
        val open: List<Connection>
        synchronized(lock) {
            serverJob?.cancel()
            serverJob = null
            serverSocket?.let(::closeQuietly)
            serverSocket = null
            open = connections.values.toList()
        }
        open.forEach { it.close() }
    }

    // ------------------------------------------------------------------
    // Outbound connections
    // ------------------------------------------------------------------

    override fun connect(address: String) {
        val bluetooth = adapter ?: return
        if (!isBluetoothEnabled()) return
        synchronized(lock) {
            if (connections.containsKey(address)) return
        }
        if (_peerStates.value[address]?.status == ConnectionStatus.CONNECTING) return
        setPeer(address) { PeerState(ConnectionStatus.CONNECTING, it?.peerName) }
        scope.launch(Dispatchers.IO) {
            try {
                bluetooth.cancelDiscovery()
            } catch (e: SecurityException) {
                // Discovery permission missing; connecting may still work.
            }
            val socket = try {
                val device = bluetooth.getRemoteDevice(address)
                device.createRfcommSocketToServiceRecord(SERVICE_UUID).also { it.connect() }
            } catch (e: Exception) {
                setPeer(address) { PeerState(ConnectionStatus.DISCONNECTED, it?.peerName) }
                return@launch
            }
            onSocketConnected(socket)
        }
    }

    fun disconnect(address: String) {
        connectionFor(address)?.close()
    }

    // ------------------------------------------------------------------
    // Messaging API used by the UI
    // ------------------------------------------------------------------

    override fun sendMessage(address: String, body: String) {
        val text = body.trim()
        if (text.isEmpty()) return
        scope.launch {
            repository.ensureConversation(address, null)
            val message = Message(
                id = UUID.randomUUID().toString(),
                conversationAddress = address,
                body = text,
                timestamp = System.currentTimeMillis(),
                isMine = true,
                status = MessageStatus.PENDING,
                isRead = true,
            )
            repository.recordOutgoing(message)
            val connection = connectionFor(address)
            if (connection != null) {
                flushPending(address, connection)
            } else {
                connect(address)
            }
        }
    }

    override fun sendAttachment(address: String, uri: Uri) {
        scope.launch(Dispatchers.IO) {
            val attachment = fileTransfer.importOutgoing(uri) ?: return@launch
            repository.ensureConversation(address, null)
            val message = Message(
                id = UUID.randomUUID().toString(),
                conversationAddress = address,
                body = attachment.name,
                timestamp = System.currentTimeMillis(),
                isMine = true,
                status = MessageStatus.PENDING,
                isRead = true,
                attachmentPath = attachment.path,
                attachmentName = attachment.name,
                attachmentMime = attachment.mime,
            )
            repository.recordOutgoing(message)
            val connection = connectionFor(address)
            if (connection != null) {
                flushPending(address, connection)
            } else {
                connect(address)
            }
        }
    }

    override fun sendTyping(address: String, active: Boolean) {
        val connection = connectionFor(address) ?: return
        scope.launch { connection.send(Frame.Typing(active)) }
    }

    /** Marks the conversation read locally and tells the peer, WhatsApp-style. */
    override fun markConversationSeen(address: String) {
        scope.launch {
            val ids = repository.markConversationSeen(address)
            if (ids.isNotEmpty()) {
                connectionFor(address)?.send(Frame.Read(ids))
            }
        }
    }

    override fun broadcast(frame: Frame, exceptAddress: String?) {
        val targets = synchronized(lock) {
            connections.filterKeys { it != exceptAddress }.values.toList()
        }
        scope.launch { targets.forEach { it.send(frame) } }
    }

    // ------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------

    private fun connectionFor(address: String): Connection? = synchronized(lock) {
        connections[address]
    }

    private fun onSocketConnected(socket: BluetoothSocket) {
        val address = socket.remoteDevice.address
        val connection = Connection(address, socket)
        val previous = synchronized(lock) { connections.put(address, connection) }
        previous?.close()
        setPeer(address) { PeerState(ConnectionStatus.CONNECTED, it?.peerName) }
        scope.launch(Dispatchers.IO) {
            connection.send(Frame.Hello(settings.displayName.value, settings.peerId))
            val deviceName = try {
                socket.remoteDevice.name
            } catch (e: SecurityException) {
                null
            }
            repository.ensureConversation(address, deviceName)
            flushPending(address, connection)
            connection.readLoop()
        }
    }

    private fun onConnectionClosed(address: String, connection: Connection) {
        val removed = synchronized(lock) {
            if (connections[address] === connection) {
                connections.remove(address)
                true
            } else {
                false
            }
        }
        if (removed) {
            setPeer(address) { PeerState(ConnectionStatus.DISCONNECTED, it?.peerName) }
            _typingPeers.update { it - address }
        }
    }

    /** Sends every queued message for [address] in order, oldest first. */
    private suspend fun flushPending(address: String, connection: Connection) {
        connection.flushMutex.withLock {
            for (message in repository.pendingFor(address)) {
                val sent = if (message.attachmentPath != null) {
                    fileTransfer.sendFile(
                        message.attachmentPath,
                        message.attachmentName ?: "file",
                        message.attachmentMime ?: "application/octet-stream",
                        message.id,
                    ) { frame -> connection.send(frame) }
                } else {
                    connection.send(Frame.Text(message.id, message.body, message.timestamp))
                }
                if (!sent) return
                repository.markSent(message.id)
            }
        }
    }

    private suspend fun handleFrame(address: String, frame: Frame) {
        when (frame) {
            is Frame.Hello -> {
                setPeer(address) { PeerState(ConnectionStatus.CONNECTED, frame.name) }
                repository.ensureConversation(address, frame.name)
                if (frame.peerId.isNotEmpty()) repository.setPeerId(address, frame.peerId)
            }
            is Frame.Text -> {
                val onScreen = activeConversation == address
                val message = Message(
                    id = frame.id,
                    conversationAddress = address,
                    body = frame.body,
                    timestamp = System.currentTimeMillis(),
                    isMine = false,
                    status = MessageStatus.DELIVERED,
                    isRead = onScreen,
                )
                repository.recordIncoming(message)
                val connection = connectionFor(address)
                connection?.send(Frame.Delivered(frame.id))
                if (onScreen) {
                    connection?.send(Frame.Read(listOf(frame.id)))
                } else {
                    _incoming.tryEmit(message)
                }
            }
            is Frame.Delivered -> repository.markDelivered(frame.id)
            is Frame.Read -> repository.markRead(frame.ids)
            is Frame.Typing -> _typingPeers.update {
                if (frame.active) it + address else it - address
            }
            is Frame.FileStart -> fileTransfer.startIncoming(frame.id, frame.name, frame.mime)
            is Frame.FileData -> fileTransfer.appendIncoming(frame.id, frame.data)
            is Frame.FileEnd -> {
                val attachment = fileTransfer.finishIncoming(frame.id) ?: return
                val onScreen = activeConversation == address
                val message = Message(
                    id = frame.id,
                    conversationAddress = address,
                    body = attachment.name,
                    timestamp = System.currentTimeMillis(),
                    isMine = false,
                    status = MessageStatus.DELIVERED,
                    isRead = onScreen,
                    attachmentPath = attachment.path,
                    attachmentName = attachment.name,
                    attachmentMime = attachment.mime,
                )
                repository.recordIncoming(message)
                val connection = connectionFor(address)
                connection?.send(Frame.Delivered(frame.id))
                if (onScreen) {
                    connection?.send(Frame.Read(listOf(frame.id)))
                } else {
                    _incoming.tryEmit(message)
                }
            }
            is Frame.GroupInvite -> onGroupFrame?.invoke(address, frame)
            is Frame.GroupText -> onGroupFrame?.invoke(address, frame)
        }
    }

    private fun setPeer(address: String, transform: (PeerState?) -> PeerState) {
        _peerStates.update { it + (address to transform(it[address])) }
    }

    private fun closeQuietly(closeable: Closeable) {
        try {
            closeable.close()
        } catch (e: IOException) {
            // Nothing useful to do.
        }
    }

    private inner class Connection(
        val address: String,
        private val socket: BluetoothSocket,
    ) {
        private val input = DataInputStream(socket.inputStream)
        private val output = DataOutputStream(BufferedOutputStream(socket.outputStream))
        private val writeLock = Any()
        val flushMutex = Mutex()

        @Volatile
        private var closed = false

        /** Returns false (and closes the link) if the peer is gone. */
        suspend fun send(frame: Frame): Boolean = withContext(Dispatchers.IO) {
            try {
                synchronized(writeLock) { ChatProtocol.write(output, frame) }
                true
            } catch (e: IOException) {
                close()
                false
            }
        }

        suspend fun readLoop() {
            try {
                while (true) {
                    val frame = ChatProtocol.read(input) ?: continue
                    handleFrame(address, frame)
                }
            } catch (e: IOException) {
                // Peer disconnected or Bluetooth went down.
            } finally {
                close()
            }
        }

        fun close() {
            if (closed) return
            closed = true
            try {
                socket.close()
            } catch (e: IOException) {
                // Nothing useful to do.
            }
            onConnectionClosed(address, this)
        }
    }

    companion object {
        /** Identifies the BlueTalk RFCOMM service in SDP; must match on both devices. */
        val SERVICE_UUID: UUID = UUID.fromString("6f9a2b40-1f2c-4c9e-8bd8-13d27a3cbe5f")
        const val SDP_SERVICE_NAME = "BlueTalk"
        private const val RETRY_DELAY_MS = 3_000L
    }
}
