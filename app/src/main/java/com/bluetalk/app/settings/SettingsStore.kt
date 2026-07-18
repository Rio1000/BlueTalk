package com.bluetalk.app.settings

import android.content.Context
import android.os.Build
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Tiny preference wrapper for the profile the user shares with peers. */
class SettingsStore(context: Context) {

    private val prefs = context.getSharedPreferences("bluetalk", Context.MODE_PRIVATE)

    private val _displayName = MutableStateFlow(prefs.getString(KEY_DISPLAY_NAME, null) ?: defaultName())
    val displayName: StateFlow<String> = _displayName.asStateFlow()

    fun setDisplayName(name: String) {
        val value = name.trim().ifEmpty { defaultName() }
        prefs.edit().putString(KEY_DISPLAY_NAME, value).apply()
        _displayName.value = value
    }

    private fun defaultName(): String = Build.MODEL ?: "BlueTalk user"

    companion object {
        private const val KEY_DISPLAY_NAME = "display_name"
    }
}
