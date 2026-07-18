package com.bluetalk.app.ui

import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.bluetalk.app.bluetooth.ConnectionStatus
import com.bluetalk.app.bluetooth.PeerState
import com.bluetalk.app.data.Message
import com.bluetalk.app.data.MessageStatus

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatScreen(address: String, onBack: () -> Unit) {
    val container = appContainer()
    val viewModel: ChatViewModel = viewModel(key = "chat-$address") {
        ChatViewModel(container, address)
    }
    val messages by viewModel.messages.collectAsStateWithLifecycle()
    val title by viewModel.title.collectAsStateWithLifecycle()
    val peer by viewModel.peerState.collectAsStateWithLifecycle()
    val typing by viewModel.peerTyping.collectAsStateWithLifecycle()
    var draft by rememberSaveable { mutableStateOf("") }
    val listState = rememberLazyListState()

    val pickAttachment = rememberLauncherForActivityResult(
        ActivityResultContracts.GetContent(),
    ) { uri ->
        if (uri != null) viewModel.sendAttachment(uri)
    }

    DisposableEffect(address) {
        viewModel.onOpen()
        onDispose { viewModel.onClose() }
    }

    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) listState.animateScrollToItem(0)
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(
                            statusLabel(peer, typing),
                            style = MaterialTheme.typography.labelSmall,
                            color = when {
                                typing -> MaterialTheme.colorScheme.primary
                                peer.status == ConnectionStatus.CONNECTED -> Color(0xFF4CAF50)
                                else -> MaterialTheme.colorScheme.onSurfaceVariant
                            },
                        )
                    }
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    if (peer.status == ConnectionStatus.DISCONNECTED) {
                        TextButton(onClick = viewModel::connect) { Text("Connect") }
                    }
                },
            )
        },
        bottomBar = {
            MessageInput(
                value = draft,
                onChange = {
                    draft = it
                    viewModel.onDraftChanged(it)
                },
                onSend = {
                    viewModel.send(draft)
                    draft = ""
                },
                onAttach = { pickAttachment.launch("*/*") },
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            state = listState,
            reverseLayout = true,
            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            if (typing) {
                item(key = "typing") { TypingBubble() }
            }
            items(messages, key = { it.id }) { message ->
                MessageBubble(message)
            }
        }
    }
}

private fun statusLabel(peer: PeerState, typing: Boolean): String = when {
    typing -> "typing…"
    peer.status == ConnectionStatus.CONNECTED -> "connected"
    peer.status == ConnectionStatus.CONNECTING -> "connecting…"
    else -> "not connected"
}

@Composable
private fun MessageBubble(message: Message) {
    val mine = message.isMine
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = if (mine) Arrangement.End else Arrangement.Start,
    ) {
        Surface(
            color = if (mine) {
                MaterialTheme.colorScheme.primary
            } else {
                MaterialTheme.colorScheme.surfaceVariant
            },
            contentColor = if (mine) {
                MaterialTheme.colorScheme.onPrimary
            } else {
                MaterialTheme.colorScheme.onSurfaceVariant
            },
            shape = RoundedCornerShape(
                topStart = 18.dp,
                topEnd = 18.dp,
                bottomStart = if (mine) 18.dp else 4.dp,
                bottomEnd = if (mine) 4.dp else 18.dp,
            ),
            modifier = Modifier.widthIn(max = 300.dp),
        ) {
            Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
                Attachment(message)
                Row(
                    modifier = Modifier.align(Alignment.End),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text(
                        formatTimeOfDay(message.timestamp),
                        style = MaterialTheme.typography.labelSmall,
                        color = LocalContentColor.current.copy(alpha = 0.7f),
                    )
                    if (mine) {
                        Text(
                            statusTicks(message.status),
                            style = MaterialTheme.typography.labelSmall,
                            color = if (message.status == MessageStatus.READ) {
                                Color(0xFF80DEEA)
                            } else {
                                LocalContentColor.current.copy(alpha = 0.7f)
                            },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun Attachment(message: Message) {
    val path = message.attachmentPath
    when {
        path != null && message.attachmentMime?.startsWith("image/") == true -> {
            val bitmap = remember(path) { BitmapFactory.decodeFile(path)?.asImageBitmap() }
            if (bitmap != null) {
                Image(
                    bitmap = bitmap,
                    contentDescription = message.attachmentName,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier
                        .sizeIn(maxWidth = 240.dp, maxHeight = 280.dp)
                        .clip(RoundedCornerShape(12.dp)),
                )
            } else {
                Text("🖼 ${message.attachmentName ?: "Image"}", style = MaterialTheme.typography.bodyLarge)
            }
        }
        path != null -> {
            Text(
                "📎 ${message.attachmentName ?: message.body}",
                style = MaterialTheme.typography.bodyLarge,
            )
        }
        else -> {
            Text(message.body, style = MaterialTheme.typography.bodyLarge)
        }
    }
}

private fun statusTicks(status: MessageStatus): String = when (status) {
    MessageStatus.PENDING -> "🕓"
    MessageStatus.SENT -> "✓"
    MessageStatus.DELIVERED, MessageStatus.READ -> "✓✓"
}

@Composable
private fun TypingBubble() {
    val transition = rememberInfiniteTransition(label = "typing")
    val alpha by transition.animateFloat(
        initialValue = 0.3f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(600), RepeatMode.Reverse),
        label = "typingAlpha",
    )
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Start) {
        Surface(
            color = MaterialTheme.colorScheme.surfaceVariant,
            contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
            shape = RoundedCornerShape(18.dp),
        ) {
            Text(
                "• • •",
                modifier = Modifier
                    .padding(horizontal = 16.dp, vertical = 10.dp)
                    .alpha(alpha),
                style = MaterialTheme.typography.bodyLarge,
            )
        }
    }
}

@Composable
private fun MessageInput(
    value: String,
    onChange: (String) -> Unit,
    onSend: () -> Unit,
    onAttach: () -> Unit,
) {
    Surface(tonalElevation = 3.dp) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(8.dp),
            verticalAlignment = Alignment.Bottom,
        ) {
            IconButton(onClick = onAttach) {
                Icon(Icons.Default.Add, contentDescription = "Attach file or photo")
            }
            OutlinedTextField(
                value = value,
                onValueChange = onChange,
                modifier = Modifier.weight(1f),
                placeholder = { Text("Message") },
                maxLines = 4,
                shape = RoundedCornerShape(24.dp),
            )
            Spacer(Modifier.width(8.dp))
            FilledIconButton(
                onClick = onSend,
                enabled = value.isNotBlank(),
            ) {
                Icon(Icons.AutoMirrored.Filled.Send, contentDescription = "Send")
            }
        }
    }
}
