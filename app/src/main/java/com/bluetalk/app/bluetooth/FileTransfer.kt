package com.bluetalk.app.bluetooth

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Base64
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/** A file stored locally, ready to attach to a message or render. */
data class Attachment(val path: String, val name: String, val mime: String)

/**
 * Moves files between devices over the chat channel. Because a whole image
 * far exceeds one frame, a file is sent as a [Frame.FileStart], a run of
 * ordered [Frame.FileData] slices, and a [Frame.FileEnd]; the receiver
 * streams the slices straight to disk. Outgoing images are downscaled and
 * re-encoded so a photo doesn't take minutes over Bluetooth.
 *
 * Used by both the RFCOMM and BLE managers; each transfer is keyed by a
 * globally unique id so concurrent transfers never interleave.
 */
class FileTransfer(context: Context) {

    private val appContext = context.applicationContext
    private val dir = File(appContext.filesDir, "attachments").apply { mkdirs() }

    private class Partial(
        val name: String,
        val mime: String,
        val file: File,
        val out: BufferedOutputStream,
    )

    private val partials = ConcurrentHashMap<String, Partial>()

    // ---- Receiving ---------------------------------------------------

    fun startIncoming(id: String, name: String, mime: String) {
        val file = File(dir, "$id-${sanitize(name)}")
        partials[id] = Partial(name, mime, file, BufferedOutputStream(FileOutputStream(file)))
    }

    fun appendIncoming(id: String, base64: String) {
        val partial = partials[id] ?: return
        try {
            partial.out.write(Base64.decode(base64, Base64.NO_WRAP))
        } catch (e: IllegalArgumentException) {
            // Corrupt slice; drop it.
        }
    }

    fun finishIncoming(id: String): Attachment? {
        val partial = partials.remove(id) ?: return null
        return try {
            partial.out.flush()
            partial.out.close()
            Attachment(partial.file.absolutePath, partial.name, partial.mime)
        } catch (e: Exception) {
            null
        }
    }

    fun abortIncoming(id: String) {
        partials.remove(id)?.let {
            try {
                it.out.close()
                it.file.delete()
            } catch (e: Exception) {
                // Ignore.
            }
        }
    }

    // ---- Sending -----------------------------------------------------

    /**
     * Copies a picked content Uri into app storage, downscaling and
     * recompressing images. Returns null if the file can't be read.
     */
    fun importOutgoing(uri: Uri): Attachment? {
        val resolver = appContext.contentResolver
        val mime = resolver.getType(uri) ?: "application/octet-stream"
        val name = queryName(uri) ?: "file"
        val id = UUID.randomUUID().toString()
        return try {
            if (mime.startsWith("image/")) {
                val bitmap = resolver.openInputStream(uri).use { BitmapFactory.decodeStream(it) }
                    ?: return null
                val scaled = downscale(bitmap, MAX_IMAGE_DIMENSION)
                val file = File(dir, "$id-${sanitize(name.substringBeforeLast('.'))}.jpg")
                FileOutputStream(file).use { scaled.compress(Bitmap.CompressFormat.JPEG, 80, it) }
                Attachment(file.absolutePath, file.name, "image/jpeg")
            } else {
                val file = File(dir, "$id-${sanitize(name)}")
                resolver.openInputStream(uri).use { input ->
                    FileOutputStream(file).use { output -> input?.copyTo(output) }
                }
                Attachment(file.absolutePath, name, mime)
            }
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Streams a file to a peer as protocol frames, passing each to [send].
     * [send] returns false when the link died, aborting the transfer.
     * Returns whether the whole file was handed off.
     */
    suspend fun sendFile(
        path: String,
        name: String,
        mime: String,
        id: String,
        send: suspend (Frame) -> Boolean,
    ): Boolean {
        val file = File(path)
        if (!send(Frame.FileStart(id, name, mime, file.length()))) return false
        val input = FileInputStream(file)
        try {
            val buffer = ByteArray(CHUNK)
            var seq = 0
            while (true) {
                val read = input.read(buffer)
                if (read <= 0) break
                val slice = if (read == buffer.size) buffer else buffer.copyOf(read)
                val encoded = Base64.encodeToString(slice, Base64.NO_WRAP)
                if (!send(Frame.FileData(id, seq++, encoded))) return false
            }
        } finally {
            input.close()
        }
        return send(Frame.FileEnd(id))
    }

    private fun downscale(bitmap: Bitmap, max: Int): Bitmap {
        val width = bitmap.width
        val height = bitmap.height
        if (width <= max && height <= max) return bitmap
        val ratio = minOf(max.toFloat() / width, max.toFloat() / height)
        return Bitmap.createScaledBitmap(bitmap, (width * ratio).toInt(), (height * ratio).toInt(), true)
    }

    private fun queryName(uri: Uri): String? {
        val cursor = appContext.contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        ) ?: return null
        cursor.use {
            if (it.moveToFirst()) {
                val index = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) return it.getString(index)
            }
        }
        return null
    }

    private fun sanitize(name: String): String =
        name.replace(Regex("[^A-Za-z0-9._-]"), "_").take(80).ifEmpty { "file" }

    companion object {
        private const val CHUNK = 8 * 1024
        private const val MAX_IMAGE_DIMENSION = 1280
    }
}
