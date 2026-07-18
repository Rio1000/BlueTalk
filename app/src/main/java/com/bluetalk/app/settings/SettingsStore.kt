package com.bluetalk.app.settings

import android.content.Context
import android.os.Build
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.UUID

/** Tiny preference wrapper for the profile the user shares with peers. */
class SettingsStore(context: Context) {

    private val prefs = context.getSharedPreferences("bluetalk", Context.MODE_PRIVATE)

    private val _displayName = MutableStateFlow(prefs.getString(KEY_DISPLAY_NAME, null) ?: defaultName())
    val displayName: StateFlow<String> = _displayName.asStateFlow()

    /**
     * Stable random identity for this install, announced in the BLE hello
     * frame. BLE hardware addresses are randomized and hidden, so peers
     * key cross-platform conversations by this instead.
     */
    val peerId: String = prefs.getString(KEY_PEER_ID, null) ?: UUID.randomUUID().toString().also {
        prefs.edit().putString(KEY_PEER_ID, it).apply()
    }

    /** Whether the user has picked a display name (drives first-run onboarding). */
    val hasChosenName: Boolean
        get() = prefs.getBoolean(KEY_NAME_CHOSEN, false)

    fun setDisplayName(name: String) {
        val value = name.trim().ifEmpty { defaultName() }
        prefs.edit()
            .putString(KEY_DISPLAY_NAME, value)
            .putBoolean(KEY_NAME_CHOSEN, true)
            .apply()
        _displayName.value = value
    }

    /** A sensible starting suggestion for the name-entry screen. */
    fun suggestedName(): String = defaultName()

    private fun defaultName(): String = Build.MODEL ?: "BlueTalk user"

    companion object {
        private const val KEY_DISPLAY_NAME = "display_name"
        private const val KEY_PEER_ID = "peer_id"
        private const val KEY_NAME_CHOSEN = "name_chosen"
    }
}
