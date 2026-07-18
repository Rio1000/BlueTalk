package com.bluetalk.app.bluetooth.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.ParcelUuid
import com.bluetalk.app.bluetooth.ChatProtocol
import com.bluetalk.app.bluetooth.ConnectionStatus
import com.bluetalk.app.bluetooth.Frame
import com.bluetalk.app.bluetooth.MessageTransport
import com.bluetalk.app.bluetooth.PeerState
import com.bluetalk.app.data.ChatRepository
import com.bluetalk.app.data.Message
import com.bluetalk.app.data.MessageStatus
import com.bluetalk.app.settings.SettingsStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.ArrayDeque
import java.util.UUID

/** A device advertising the BlueTalk service, shown on the Discover screen. */
data class BleDevice(val address: String, val name: String?)

/**
 * Bluetooth Low Energy transport, interoperable with the iOS app. Every
 * device plays both GATT roles at once: it advertises the BlueTalk service
 * (peripheral) so others can connect, and scans/connects to that service
 * (central). Chat frames are the same JSON as RFCOMM, chunked to the ATT
 * MTU (see [BleProtocol]).
 *
 * Conversations are keyed by the peer's install-stable id announced in the
 * hello frame, because BLE hardware addresses are randomized and hidden.
 *
 * Runtime Bluetooth permissions are checked in the UI before these entry
 * points run; adapter calls are additionally guarded so a revoked
 * permission degrades to a disconnect instead of a crash.
 */
@SuppressLint("MissingPermission")
class BleConnectionManager(
    context: Context,
    private val repository: ChatRepository,
    private val settings: SettingsStore,
    private val scope: CoroutineScope,
) : MessageTransport {

    private val appContext = context.applicationContext
    private val bluetoothManager =
        appContext.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager

    private val adapter: BluetoothAdapter?
        get() = bluetoothManager.adapter

    private val lock = Any()

    // Peripheral role.
    private var gattServer: BluetoothGattServer? = null
    private var txCharacteristic: BluetoothGattCharacteristic? = null
    private var advertising = false

    // Links, indexed for connection management and message routing.
    private val links = mutableMapOf<String, BleLink>() // by device address
    private val linksByPeer = mutableMapOf<String, BleLink>() // by peerId
    private val rememberedDevices = mutableMapOf<String, BluetoothDevice>() // peerId -> device
    private val scannedDevices = mutableMapOf<String, BluetoothDevice>() // address -> device
    private val connectingDevices = mutableSetOf<String>()

    // Global serialized notify queue for the peripheral role (one TX char,
    // shared across centrals, so notifications must not overlap).
    private val notifyQueue = ArrayDeque<Pair<BluetoothDevice, ByteArray>>()
    private var notifyInFlight = false

    private val _peerStates = MutableStateFlow<Map<String, PeerState>>(emptyMap())
    override val peerStates: StateFlow<Map<String, PeerState>> = _peerStates.asStateFlow()

    private val _typingPeers = MutableStateFlow<Set<String>>(emptySet())
    override val typingPeers: StateFlow<Set<String>> = _typingPeers.asStateFlow()

    private val _incoming = MutableSharedFlow<Message>(extraBufferCapacity = 32)
    override val incoming: SharedFlow<Message> = _incoming.asSharedFlow()

    @Volatile
    override var activeConversation: String? = null

    private val _discovered = MutableStateFlow<List<BleDevice>>(emptyList())
    val discovered: StateFlow<List<BleDevice>> = _discovered.asStateFlow()

    private val _scanning = MutableStateFlow(false)
    val scanning: StateFlow<Boolean> = _scanning.asStateFlow()

    fun isBluetoothEnabled(): Boolean = try {
        adapter?.isEnabled == true
    } catch (e: SecurityException) {
        false
    }

    // ------------------------------------------------------------------
    // Peripheral role: advertise + accept inbound centrals
    // ------------------------------------------------------------------

    override fun startServer() {
        synchronized(lock) {
            if (gattServer != null || !isBluetoothEnabled()) return
            val server = try {
                bluetoothManager.openGattServer(appContext, serverCallback)
            } catch (e: SecurityException) {
                return
            } ?: return

            val service = BluetoothGattService(
                BleProtocol.SERVICE_UUID,
                BluetoothGattService.SERVICE_TYPE_PRIMARY,
            )
            val tx = BluetoothGattCharacteristic(
                BleProtocol.TX_UUID,
                BluetoothGattCharacteristic.PROPERTY_NOTIFY,
                BluetoothGattCharacteristic.PERMISSION_READ,
            )
            tx.addDescriptor(
                BluetoothGattDescriptor(
                    BleProtocol.CCCD_UUID,
                    BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE,
                )
            )
            val rx = BluetoothGattCharacteristic(
                BleProtocol.RX_UUID,
                BluetoothGattCharacteristic.PROPERTY_WRITE or
                    BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
                BluetoothGattCharacteristic.PERMISSION_WRITE,
            )
            service.addCharacteristic(tx)
            service.addCharacteristic(rx)
            try {
                server.addService(service)
            } catch (e: SecurityException) {
                return
            }
            gattServer = server
            txCharacteristic = tx
        }
        startAdvertising()
    }

    private fun startAdvertising() {
        val advertiser = try {
            adapter?.bluetoothLeAdvertiser
        } catch (e: SecurityException) {
            null
        } ?: return
        if (advertising) return
        val settingsBuilder = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .setTimeout(0)
        val data = AdvertiseData.Builder()
            .addServiceUuid(ParcelUuid(BleProtocol.SERVICE_UUID))
            .build()
        // The display name is exchanged in the hello frame; the adapter name
        // rides in the scan response purely so scanners can show something.
        val scanResponse = AdvertiseData.Builder()
            .setIncludeDeviceName(true)
            .build()
        try {
            advertiser.startAdvertising(settingsBuilder.build(), data, scanResponse, advertiseCallback)
        } catch (e: SecurityException) {
            // Advertising permission missing; the central role still works.
        }
    }

    fun shutdown() {
        synchronized(lock) {
            try {
                adapter?.bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback)
            } catch (e: SecurityException) {
                // Ignore.
            }
            advertising = false
            links.values.toList().forEach { it.close() }
            links.clear()
            linksByPeer.clear()
            try {
                gattServer?.close()
            } catch (e: SecurityException) {
                // Ignore.
            }
            gattServer = null
            txCharacteristic = null
        }
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
            advertising = true
        }

        override fun onStartFailure(errorCode: Int) {
            advertising = false
        }
    }

    // ------------------------------------------------------------------
    // Central role: scan + connect out
    // ------------------------------------------------------------------

    fun startScan() {
        val scanner = try {
            adapter?.bluetoothLeScanner
        } catch (e: SecurityException) {
            null
        } ?: return
        _discovered.value = emptyList()
        scannedDevices.clear()
        val filters = listOf(
            ScanFilter.Builder().setServiceUuid(ParcelUuid(BleProtocol.SERVICE_UUID)).build()
        )
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
        try {
            scanner.startScan(filters, settings, scanCallback)
            _scanning.value = true
        } catch (e: SecurityException) {
            _scanning.value = false
        }
    }

    fun stopScan() {
        try {
            adapter?.bluetoothLeScanner?.stopScan(scanCallback)
        } catch (e: SecurityException) {
            // Ignore.
        }
        _scanning.value = false
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val device = result.device
            scannedDevices[device.address] = device
            val name = result.scanRecord?.deviceName ?: try {
                device.name
            } catch (e: SecurityException) {
                null
            }
            val entry = BleDevice(device.address, name)
            _discovered.update { list ->
                if (list.any { it.address == entry.address }) {
                    list.map { if (it.address == entry.address) entry else it }
                } else {
                    list + entry
                }
            }
        }
    }

    /** Connects to a device tapped on the Discover screen. */
    fun connectDevice(address: String) {
        val device = scannedDevices[address] ?: try {
            adapter?.getRemoteDevice(address)
        } catch (e: IllegalArgumentException) {
            null
        } ?: return
        connect(device, expectedPeerId = null)
    }

    /** Reconnects to a known conversation ([address] is the peer id). */
    override fun connect(address: String) {
        if (linksByPeer.containsKey(address)) return
        val device = rememberedDevices[address] ?: return
        setPeer(address) { PeerState(ConnectionStatus.CONNECTING, it?.peerName) }
        connect(device, expectedPeerId = address)
    }

    private fun connect(device: BluetoothDevice, expectedPeerId: String?) {
        if (!isBluetoothEnabled()) return
        synchronized(lock) {
            if (links.containsKey(device.address) || device.address in connectingDevices) return
            connectingDevices.add(device.address)
        }
        try {
            adapter?.bluetoothLeScanner?.stopScan(scanCallback)
        } catch (e: SecurityException) {
            // Ignore.
        }
        try {
            device.connectGatt(appContext, false, ClientLink(expectedPeerId), BluetoothDevice.TRANSPORT_LE)
        } catch (e: SecurityException) {
            synchronized(lock) { connectingDevices.remove(device.address) }
        }
    }

    // ------------------------------------------------------------------
    // Messaging API (keys are peer ids)
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
            val link = linkFor(address)
            if (link != null) {
                flushPending(address, link)
            } else {
                connect(address)
            }
        }
    }

    override fun sendTyping(address: String, active: Boolean) {
        linkFor(address)?.sendFrame(Frame.Typing(active))
    }

    override fun markConversationSeen(address: String) {
        scope.launch {
            val ids = repository.markConversationSeen(address)
            if (ids.isNotEmpty()) {
                linkFor(address)?.sendFrame(Frame.Read(ids))
            }
        }
    }

    private fun linkFor(peerId: String): BleLink? = synchronized(lock) { linksByPeer[peerId] }

    private fun flushPending(peerId: String, link: BleLink) {
        scope.launch {
            for (message in repository.pendingFor(peerId)) {
                link.sendFrame(Frame.Text(message.id, message.body, message.timestamp))
                repository.markSent(message.id)
            }
        }
    }

    // ------------------------------------------------------------------
    // Frame handling (shared by both roles)
    // ------------------------------------------------------------------

    private fun onFrameReceived(link: BleLink, bytes: ByteArray) {
        val frame = ChatProtocol.decode(bytes) ?: return
        when (frame) {
            is Frame.Hello -> {
                val peerId = frame.peerId
                if (peerId.isEmpty()) return
                link.peerId = peerId
                synchronized(lock) {
                    linksByPeer[peerId] = link
                    link.device?.let { rememberedDevices[peerId] = it }
                    connectingDevices.remove(link.address)
                }
                setPeer(peerId) { PeerState(ConnectionStatus.CONNECTED, frame.name) }
                scope.launch {
                    repository.ensureConversation(peerId, frame.name)
                    flushPending(peerId, link)
                }
            }
            is Frame.Text -> {
                val peerId = link.peerId ?: return
                val onScreen = activeConversation == peerId
                scope.launch {
                    val message = Message(
                        id = frame.id,
                        conversationAddress = peerId,
                        body = frame.body,
                        timestamp = System.currentTimeMillis(),
                        isMine = false,
                        status = MessageStatus.DELIVERED,
                        isRead = onScreen,
                    )
                    repository.recordIncoming(message)
                    link.sendFrame(Frame.Delivered(frame.id))
                    if (onScreen) {
                        link.sendFrame(Frame.Read(listOf(frame.id)))
                    } else {
                        _incoming.tryEmit(message)
                    }
                }
            }
            is Frame.Delivered -> scope.launch { repository.markDelivered(frame.id) }
            is Frame.Read -> scope.launch { repository.markRead(frame.ids) }
            is Frame.Typing -> {
                val peerId = link.peerId ?: return
                _typingPeers.update { if (frame.active) it + peerId else it - peerId }
            }
        }
    }

    private fun onLinkClosed(link: BleLink) {
        val peerId = synchronized(lock) {
            links.remove(link.address)
            connectingDevices.remove(link.address)
            val id = link.peerId
            if (id != null && linksByPeer[id] === link) {
                linksByPeer.remove(id)
                id
            } else {
                null
            }
        }
        if (peerId != null) {
            setPeer(peerId) { PeerState(ConnectionStatus.DISCONNECTED, it?.peerName) }
            _typingPeers.update { it - peerId }
        }
    }

    private fun setPeer(peerId: String, transform: (PeerState?) -> PeerState) {
        _peerStates.update { it + (peerId to transform(it[peerId])) }
    }

    // ------------------------------------------------------------------
    // Peripheral notify queue (serialized across all centrals)
    // ------------------------------------------------------------------

    @Synchronized
    private fun enqueueNotify(device: BluetoothDevice, chunks: List<ByteArray>) {
        chunks.forEach { notifyQueue.add(device to it) }
        pumpNotify()
    }

    @Suppress("DEPRECATION")
    @Synchronized
    private fun pumpNotify() {
        if (notifyInFlight) return
        val server = gattServer ?: return
        val tx = txCharacteristic ?: return
        val head = notifyQueue.peek() ?: return
        tx.value = head.second
        notifyInFlight = true
        val ok = try {
            server.notifyCharacteristicChanged(head.first, tx, false)
        } catch (e: SecurityException) {
            false
        }
        if (ok) {
            notifyQueue.poll()
            // Wait for onNotificationSent to clear notifyInFlight.
        } else {
            notifyInFlight = false
            scope.launch {
                delay(20)
                pumpNotify()
            }
        }
    }

    @Synchronized
    private fun onNotificationSent() {
        notifyInFlight = false
        pumpNotify()
    }

    // ------------------------------------------------------------------
    // GATT server callback
    // ------------------------------------------------------------------

    private val serverCallback = object : BluetoothGattServerCallback() {

        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                synchronized(lock) { links[device.address] as? ServerLink }?.let { onLinkClosed(it) }
            }
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray,
        ) {
            if (characteristic.uuid == BleProtocol.RX_UUID) {
                val link = serverLinkFor(device)
                link.reassembler.ingest(value)?.let { onFrameReceived(link, it) }
            }
            if (responseNeeded) {
                try {
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, null)
                } catch (e: SecurityException) {
                    // Ignore.
                }
            }
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray,
        ) {
            if (descriptor.uuid == BleProtocol.CCCD_UUID) {
                // Central subscribed to TX: the link is ready. Greet it.
                val link = serverLinkFor(device)
                link.sendFrame(Frame.Hello(settings.displayName.value, settings.peerId))
            }
            if (responseNeeded) {
                try {
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, null)
                } catch (e: SecurityException) {
                    // Ignore.
                }
            }
        }

        override fun onMtuChanged(device: BluetoothDevice, mtu: Int) {
            (synchronized(lock) { links[device.address] } as? ServerLink)?.maxPacket =
                (mtu - 3).coerceAtLeast(BleProtocol.FALLBACK_PACKET)
        }

        override fun onNotificationSent(device: BluetoothDevice, status: Int) {
            onNotificationSent()
        }
    }

    private fun serverLinkFor(device: BluetoothDevice): ServerLink = synchronized(lock) {
        (links[device.address] as? ServerLink) ?: ServerLink(device).also { links[device.address] = it }
    }

    // ------------------------------------------------------------------
    // Links
    // ------------------------------------------------------------------

    /**
     * A live BLE link. Implemented twice: [ServerLink] wraps a central that
     * connected to our GATT server (peripheral role), [ClientLink] wraps a
     * peripheral we connected to (central role). Each keeps its own
     * reassembly buffer and negotiated packet size.
     */
    private interface BleLink {
        var peerId: String?
        val reassembler: BleProtocol.Reassembler
        var maxPacket: Int
        val address: String
        val device: BluetoothDevice?
        fun sendFrame(frame: Frame)
        fun close()
    }

    /** Inbound link: a remote central subscribed to our TX characteristic. */
    private inner class ServerLink(private val central: BluetoothDevice) : BleLink {
        override var peerId: String? = null
        override val reassembler = BleProtocol.Reassembler()
        override var maxPacket = BleProtocol.FALLBACK_PACKET
        override val address: String get() = central.address
        override val device: BluetoothDevice get() = central

        override fun sendFrame(frame: Frame) {
            enqueueNotify(central, BleProtocol.chunk(ChatProtocol.encode(frame), maxPacket))
        }

        override fun close() {
            try {
                gattServer?.cancelConnection(central)
            } catch (e: SecurityException) {
                // Ignore.
            }
            onLinkClosed(this)
        }
    }

    /** Outbound link: we are the central, connected to a peer's GATT server. */
    private inner class ClientLink(private val expectedPeerId: String?) :
        android.bluetooth.BluetoothGattCallback(), BleLink {

        override var peerId: String? = null
        override val reassembler = BleProtocol.Reassembler()
        override var maxPacket = BleProtocol.FALLBACK_PACKET

        private var gatt: BluetoothGatt? = null
        private var rx: BluetoothGattCharacteristic? = null
        private val writeQueue = ArrayDeque<ByteArray>()
        private var writeInFlight = false
        private var deviceAddress: String = ""

        override val address: String get() = deviceAddress
        override val device: BluetoothDevice? get() = gatt?.device

        override fun sendFrame(frame: Frame) {
            enqueueWrite(BleProtocol.chunk(ChatProtocol.encode(frame), maxPacket))
        }

        @Synchronized
        private fun enqueueWrite(chunks: List<ByteArray>) {
            writeQueue.addAll(chunks)
            pumpWrite()
        }

        @Suppress("DEPRECATION")
        @Synchronized
        private fun pumpWrite() {
            if (writeInFlight) return
            val target = gatt ?: return
            val characteristic = rx ?: return
            val head = writeQueue.peek() ?: return
            characteristic.value = head
            characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            writeInFlight = true
            val ok = try {
                target.writeCharacteristic(characteristic)
            } catch (e: SecurityException) {
                false
            }
            if (ok) {
                writeQueue.poll()
            } else {
                writeInFlight = false
                scope.launch {
                    delay(20)
                    pumpWrite()
                }
            }
        }

        @Synchronized
        fun onWriteComplete() {
            writeInFlight = false
            pumpWrite()
        }

        override fun close() {
            val target = gatt
            gatt = null
            try {
                target?.disconnect()
                target?.close()
            } catch (e: SecurityException) {
                // Ignore.
            }
            onLinkClosed(this)
        }

        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            deviceAddress = g.device.address
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                gatt = g
                synchronized(lock) { links[deviceAddress] = this }
                try {
                    g.requestMtu(517)
                } catch (e: SecurityException) {
                    close()
                }
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                onLinkClosed(this)
                try {
                    g.close()
                } catch (e: SecurityException) {
                    // Ignore.
                }
            }
        }

        override fun onMtuChanged(g: BluetoothGatt, mtu: Int, status: Int) {
            maxPacket = (mtu - 3).coerceAtLeast(BleProtocol.FALLBACK_PACKET)
            try {
                g.discoverServices()
            } catch (e: SecurityException) {
                close()
            }
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            val service = g.getService(BleProtocol.SERVICE_UUID) ?: run { close(); return }
            rx = service.getCharacteristic(BleProtocol.RX_UUID)
            val tx = service.getCharacteristic(BleProtocol.TX_UUID) ?: run { close(); return }
            try {
                g.setCharacteristicNotification(tx, true)
                val cccd = tx.getDescriptor(BleProtocol.CCCD_UUID)
                @Suppress("DEPRECATION")
                if (cccd != null) {
                    cccd.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    g.writeDescriptor(cccd)
                }
            } catch (e: SecurityException) {
                close()
            }
        }

        override fun onDescriptorWrite(
            g: BluetoothGatt,
            descriptor: BluetoothGattDescriptor,
            status: Int,
        ) {
            // Notifications enabled: greet the peer and await their hello.
            expectedPeerId?.let { setPeer(it) { s -> PeerState(ConnectionStatus.CONNECTING, s?.peerName) } }
            sendFrame(Frame.Hello(settings.displayName.value, settings.peerId))
        }

        @Suppress("DEPRECATION")
        override fun onCharacteristicChanged(
            g: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
        ) {
            if (characteristic.uuid != BleProtocol.TX_UUID) return
            val value = characteristic.value ?: return
            reassembler.ingest(value)?.let { onFrameReceived(this, it) }
        }

        override fun onCharacteristicWrite(
            g: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            onWriteComplete()
        }
    }
}
