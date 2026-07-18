package com.bluetalk.app.bluetooth

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.bluetalk.app.BlueTalkApp
import com.bluetalk.app.MainActivity
import com.bluetalk.app.R
import com.bluetalk.app.data.Message
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Foreground service that keeps the RFCOMM server alive while the app is
 * backgrounded and raises notifications for messages that arrive when
 * their conversation is not on screen.
 */
class ChatService : Service() {

    private var serviceScope: CoroutineScope? = null

    override fun onCreate() {
        super.onCreate()
        createChannels()
        startInForeground()
        val container = (application as BlueTalkApp).container
        container.connectionManager.startServer()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        serviceScope = scope
        scope.launch {
            container.connectionManager.incoming.collect { message -> notifyMessage(message) }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        serviceScope?.cancel()
        serviceScope = null
        super.onDestroy()
    }

    private fun startInForeground() {
        val notification = NotificationCompat.Builder(this, CHANNEL_LISTENING)
            .setSmallIcon(R.drawable.ic_stat_bluetalk)
            .setContentTitle(getString(R.string.listening_title))
            .setContentText(getString(R.string.listening_text))
            .setOngoing(true)
            .setContentIntent(contentIntent(null))
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID_LISTENING,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
            )
        } else {
            startForeground(NOTIFICATION_ID_LISTENING, notification)
        }
    }

    private suspend fun notifyMessage(message: Message) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val container = (application as BlueTalkApp).container
        val title = container.repository.displayName(message.conversationAddress)
        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_MESSAGES)
            .setSmallIcon(R.drawable.ic_stat_bluetalk)
            .setContentTitle(title)
            .setContentText(message.body)
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setContentIntent(contentIntent(message.conversationAddress))
            .build()
        try {
            NotificationManagerCompat.from(this)
                .notify(message.conversationAddress.hashCode(), notification)
        } catch (e: SecurityException) {
            // Notification permission revoked mid-flight.
        }
    }

    private fun contentIntent(address: String?): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            if (address != null) putExtra(MainActivity.EXTRA_OPEN_CONVERSATION, address)
        }
        return PendingIntent.getActivity(
            this,
            address?.hashCode() ?: 0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun createChannels() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_LISTENING,
                getString(R.string.channel_listening),
                NotificationManager.IMPORTANCE_MIN,
            ),
        )
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_MESSAGES,
                getString(R.string.channel_messages),
                NotificationManager.IMPORTANCE_HIGH,
            ),
        )
    }

    companion object {
        private const val CHANNEL_LISTENING = "bluetalk.listening"
        private const val CHANNEL_MESSAGES = "bluetalk.messages"
        private const val NOTIFICATION_ID_LISTENING = 1

        fun start(context: Context) {
            ContextCompat.startForegroundService(context, Intent(context, ChatService::class.java))
        }
    }
}
