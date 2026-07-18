package com.bluetalk.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.bluetalk.app.AppContainer
import com.bluetalk.app.BlueTalkApp
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import kotlin.math.absoluteValue

@Composable
fun appContainer(): AppContainer =
    (LocalContext.current.applicationContext as BlueTalkApp).container

private val avatarPalette = listOf(
    Color(0xFF5C6BC0),
    Color(0xFF26A69A),
    Color(0xFFEF5350),
    Color(0xFFAB47BC),
    Color(0xFFFFA726),
    Color(0xFF42A5F5),
    Color(0xFF66BB6A),
    Color(0xFF8D6E63),
)

@Composable
fun Avatar(name: String, connected: Boolean, modifier: Modifier = Modifier) {
    val color = avatarPalette[name.hashCode().absoluteValue % avatarPalette.size]
    Box(modifier = modifier) {
        Box(
            modifier = Modifier
                .size(48.dp)
                .clip(CircleShape)
                .background(color),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = name.trim().take(1).uppercase().ifEmpty { "?" },
                style = MaterialTheme.typography.titleMedium,
                color = Color.White,
            )
        }
        if (connected) {
            Box(
                modifier = Modifier
                    .size(14.dp)
                    .align(Alignment.BottomEnd)
                    .clip(CircleShape)
                    .background(Color(0xFF4CAF50))
                    .border(2.dp, MaterialTheme.colorScheme.surface, CircleShape),
            )
        }
    }
}

/** Today -> "14:05", otherwise -> "3 Jun". */
fun formatTimestamp(timestamp: Long): String {
    val now = Calendar.getInstance()
    val then = Calendar.getInstance().apply { timeInMillis = timestamp }
    val sameDay = now.get(Calendar.YEAR) == then.get(Calendar.YEAR) &&
        now.get(Calendar.DAY_OF_YEAR) == then.get(Calendar.DAY_OF_YEAR)
    val pattern = if (sameDay) "HH:mm" else "d MMM"
    return SimpleDateFormat(pattern, Locale.getDefault()).format(Date(timestamp))
}

fun formatTimeOfDay(timestamp: Long): String =
    SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(timestamp))
