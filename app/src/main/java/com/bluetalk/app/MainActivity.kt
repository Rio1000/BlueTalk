package com.bluetalk.app

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.bluetalk.app.bluetooth.ChatService
import com.bluetalk.app.ui.ChatScreen
import com.bluetalk.app.ui.ConversationsScreen
import com.bluetalk.app.ui.DiscoverScreen
import com.bluetalk.app.ui.SettingsScreen
import com.bluetalk.app.ui.theme.BlueTalkTheme
import kotlinx.coroutines.flow.MutableStateFlow

class MainActivity : ComponentActivity() {

    /** Conversation addresses arriving from notification taps. */
    private val conversationRequests = MutableStateFlow<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        conversationRequests.value = intent?.getStringExtra(EXTRA_OPEN_CONVERSATION)
        setContent {
            BlueTalkTheme {
                BlueTalkRoot(conversationRequests)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        conversationRequests.value = intent.getStringExtra(EXTRA_OPEN_CONVERSATION)
    }

    companion object {
        const val EXTRA_OPEN_CONVERSATION = "open_conversation"
    }
}

fun requiredBluetoothPermissions(): Array<String> =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        arrayOf(
            Manifest.permission.BLUETOOTH_CONNECT,
            Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.BLUETOOTH_ADVERTISE,
        )
    } else {
        arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
    }

fun hasBluetoothPermissions(context: Context): Boolean =
    requiredBluetoothPermissions().all {
        ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
    }

@Composable
private fun BlueTalkRoot(conversationRequests: MutableStateFlow<String?>) {
    val context = LocalContext.current
    val container = (context.applicationContext as BlueTalkApp).container
    var nameChosen by remember { mutableStateOf(container.settings.hasChosenName) }
    var granted by remember { mutableStateOf(hasBluetoothPermissions(context)) }

    if (!nameChosen) {
        NameOnboardingScreen(
            initialName = container.settings.suggestedName(),
            onContinue = { name ->
                container.settings.setDisplayName(name)
                nameChosen = true
            },
        )
        return
    }

    if (!granted) {
        PermissionGate(onGranted = { granted = true })
        return
    }

    LaunchedEffect(Unit) { ChatService.start(context) }
    BlueTalkNavGraph(conversationRequests)
}

@Composable
private fun NameOnboardingScreen(initialName: String, onContinue: (String) -> Unit) {
    var name by rememberSaveable { mutableStateOf(initialName) }
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            "Welcome to BlueTalk",
            style = MaterialTheme.typography.headlineSmall,
            textAlign = TextAlign.Center,
        )
        Text(
            "What should people see when you message them nearby?",
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        OutlinedTextField(
            value = name,
            onValueChange = { name = it },
            label = { Text("Your name") },
            singleLine = true,
        )
        Button(
            onClick = { onContinue(name) },
            enabled = name.isNotBlank(),
        ) {
            Text("Continue")
        }
    }
}

@Composable
private fun PermissionGate(onGranted: () -> Unit) {
    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { result ->
        val required = requiredBluetoothPermissions().toSet()
        if (result.filterKeys { it in required }.values.all { it }) onGranted()
    }
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            "Nearby messaging needs Bluetooth",
            style = MaterialTheme.typography.headlineSmall,
            textAlign = TextAlign.Center,
        )
        Text(
            "BlueTalk sends and receives messages over Bluetooth instead of the internet. " +
                "Grant the Bluetooth permissions to find nearby devices and chat with them.",
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Button(onClick = {
            val permissions = requiredBluetoothPermissions().toMutableList()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                permissions += Manifest.permission.POST_NOTIFICATIONS
            }
            launcher.launch(permissions.toTypedArray())
        }) {
            Text("Grant permissions")
        }
    }
}

@Composable
private fun BlueTalkNavGraph(conversationRequests: MutableStateFlow<String?>) {
    val navController = rememberNavController()

    LaunchedEffect(navController) {
        conversationRequests.collect { address ->
            if (address != null) {
                conversationRequests.value = null
                navController.navigate("chat/$address")
            }
        }
    }

    NavHost(navController = navController, startDestination = "conversations") {
        composable("conversations") {
            ConversationsScreen(
                onOpenChat = { address -> navController.navigate("chat/$address") },
                onDiscover = { navController.navigate("discover") },
                onSettings = { navController.navigate("settings") },
            )
        }
        composable("chat/{address}") { entry ->
            val address = entry.arguments?.getString("address") ?: return@composable
            ChatScreen(address = address, onBack = { navController.popBackStack() })
        }
        composable("discover") {
            DiscoverScreen(
                onOpenChat = { address ->
                    navController.navigate("chat/$address") {
                        popUpTo("conversations")
                    }
                },
                onBack = { navController.popBackStack() },
            )
        }
        composable("settings") {
            SettingsScreen(onBack = { navController.popBackStack() })
        }
    }
}
