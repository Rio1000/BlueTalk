package com.bluetalk.app

import android.app.Application
import android.content.Context
import com.bluetalk.app.bluetooth.ConnectionManager
import com.bluetalk.app.bluetooth.DeviceDiscovery
import com.bluetalk.app.data.AppDatabase
import com.bluetalk.app.data.ChatRepository
import com.bluetalk.app.settings.SettingsStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

class BlueTalkApp : Application() {

    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
    }
}

/** Hand-rolled dependency container; one instance for the whole process. */
class AppContainer(context: Context) {

    val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    val settings = SettingsStore(context)

    private val database = AppDatabase.get(context)

    val repository = ChatRepository(database.conversationDao(), database.messageDao())

    val connectionManager = ConnectionManager(context, repository, settings, appScope)

    val discovery = DeviceDiscovery(context)
}
