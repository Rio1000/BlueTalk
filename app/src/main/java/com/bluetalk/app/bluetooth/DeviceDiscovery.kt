package com.bluetalk.app.bluetooth

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import androidx.core.content.ContextCompat
import androidx.core.content.IntentCompat
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/**
 * Wraps classic Bluetooth discovery: paired devices plus a scan for
 * nearby ones, exposed as flows the Discover screen renders live.
 */
@SuppressLint("MissingPermission")
class DeviceDiscovery(context: Context) {

    data class Device(val address: String, val name: String?, val paired: Boolean)

    private val appContext = context.applicationContext

    private val adapter: BluetoothAdapter?
        get() = (appContext.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter

    private val _found = MutableStateFlow<List<Device>>(emptyList())
    val found: StateFlow<List<Device>> = _found.asStateFlow()

    private val _scanning = MutableStateFlow(false)
    val scanning: StateFlow<Boolean> = _scanning.asStateFlow()

    private var receiverRegistered = false

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                BluetoothDevice.ACTION_FOUND -> {
                    val device = IntentCompat.getParcelableExtra(
                        intent,
                        BluetoothDevice.EXTRA_DEVICE,
                        BluetoothDevice::class.java,
                    ) ?: return
                    val name = try {
                        device.name
                    } catch (e: SecurityException) {
                        null
                    }
                    val entry = Device(
                        address = device.address,
                        name = name,
                        paired = device.bondState == BluetoothDevice.BOND_BONDED,
                    )
                    _found.update { list ->
                        if (list.any { it.address == entry.address }) {
                            list.map { if (it.address == entry.address) entry else it }
                        } else {
                            list + entry
                        }
                    }
                }
                BluetoothAdapter.ACTION_DISCOVERY_STARTED -> _scanning.value = true
                BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> _scanning.value = false
            }
        }
    }

    fun pairedDevices(): List<Device> = try {
        adapter?.bondedDevices.orEmpty().map {
            Device(it.address, it.name, paired = true)
        }
    } catch (e: SecurityException) {
        emptyList()
    }

    fun startScan() {
        val bluetooth = adapter ?: return
        if (!receiverRegistered) {
            val filter = IntentFilter().apply {
                addAction(BluetoothDevice.ACTION_FOUND)
                addAction(BluetoothAdapter.ACTION_DISCOVERY_STARTED)
                addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
            }
            ContextCompat.registerReceiver(
                appContext,
                receiver,
                filter,
                ContextCompat.RECEIVER_EXPORTED,
            )
            receiverRegistered = true
        }
        _found.value = emptyList()
        try {
            if (bluetooth.isDiscovering) bluetooth.cancelDiscovery()
            bluetooth.startDiscovery()
        } catch (e: SecurityException) {
            _scanning.value = false
        }
    }

    fun stopScan() {
        try {
            adapter?.cancelDiscovery()
        } catch (e: SecurityException) {
            // Nothing useful to do.
        }
    }
}
