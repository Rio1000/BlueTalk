package com.bluetalk.app.ui

import android.bluetooth.BluetoothAdapter
import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.bluetalk.app.bluetooth.DeviceDiscovery

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DiscoverScreen(
    onOpenChat: (String) -> Unit,
    onBack: () -> Unit,
) {
    val container = appContainer()
    val viewModel: DiscoverViewModel = viewModel { DiscoverViewModel(container) }
    val scanning by viewModel.scanning.collectAsStateWithLifecycle()
    val found by viewModel.found.collectAsStateWithLifecycle()
    val paired by viewModel.paired.collectAsStateWithLifecycle()
    var bluetoothOn by remember {
        mutableStateOf(container.connectionManager.isBluetoothEnabled())
    }

    val activityLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) {
        bluetoothOn = container.connectionManager.isBluetoothEnabled()
        if (bluetoothOn) viewModel.refreshPaired()
    }

    LaunchedEffect(Unit) { viewModel.refreshPaired() }
    DisposableEffect(Unit) {
        onDispose { viewModel.stopScan() }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("New chat") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(
                horizontal = 16.dp,
                vertical = 8.dp,
            ),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (!bluetoothOn) {
                item(key = "bt-off") {
                    Card {
                        Column(Modifier.padding(16.dp)) {
                            Text(
                                "Bluetooth is off",
                                style = MaterialTheme.typography.titleMedium,
                            )
                            Spacer(Modifier.height(4.dp))
                            Text(
                                "BlueTalk needs Bluetooth to find nearby devices and deliver messages.",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Spacer(Modifier.height(12.dp))
                            Button(onClick = {
                                activityLauncher.launch(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE))
                            }) {
                                Text("Turn on Bluetooth")
                            }
                        }
                    }
                }
            }

            item(key = "visibility") {
                Card {
                    Column(Modifier.padding(16.dp)) {
                        Text(
                            "First time chatting with someone?",
                            style = MaterialTheme.typography.titleMedium,
                        )
                        Spacer(Modifier.height(4.dp))
                        Text(
                            "One phone should tap “Make me visible”, the other should scan " +
                                "and tap the device that appears. Android will ask both of you " +
                                "to confirm pairing.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Spacer(Modifier.height(12.dp))
                        OutlinedButton(onClick = {
                            val intent = Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE)
                                .putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, 300)
                            activityLauncher.launch(intent)
                        }) {
                            Text("Make me visible")
                        }
                    }
                }
            }

            if (paired.isNotEmpty()) {
                item(key = "paired-header") { SectionHeader("Paired devices") }
                items(paired, key = { "paired-${it.address}" }) { device ->
                    DeviceRow(device) {
                        viewModel.openChat(device) { onOpenChat(device.address) }
                    }
                }
            }

            item(key = "nearby-header") {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    SectionHeader("Nearby devices")
                    Spacer(Modifier.weight(1f))
                    if (scanning) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(20.dp),
                            strokeWidth = 2.dp,
                        )
                        Spacer(Modifier.width(8.dp))
                        TextButton(onClick = viewModel::stopScan) { Text("Stop") }
                    } else {
                        TextButton(
                            onClick = viewModel::startScan,
                            enabled = bluetoothOn,
                        ) {
                            Text("Scan")
                        }
                    }
                }
            }

            val nearby = found.filter { candidate -> paired.none { it.address == candidate.address } }
            if (nearby.isEmpty()) {
                item(key = "nearby-empty") {
                    Text(
                        if (scanning) "Searching…" else "No devices found yet. Tap Scan to search.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            } else {
                items(nearby, key = { "nearby-${it.address}" }) { device ->
                    DeviceRow(device) {
                        viewModel.openChat(device) { onOpenChat(device.address) }
                    }
                }
            }
        }
    }
}

@Composable
private fun SectionHeader(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.primary,
    )
}

@Composable
private fun DeviceRow(device: DeviceDiscovery.Device, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Avatar(name = device.name ?: "?", connected = false)
        Spacer(Modifier.width(16.dp))
        Column(Modifier.weight(1f)) {
            Text(
                device.name ?: "Unknown device",
                style = MaterialTheme.typography.titleMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                device.address,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
