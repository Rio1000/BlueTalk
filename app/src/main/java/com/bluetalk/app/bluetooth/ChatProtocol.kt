package com.bluetalk.app.bluetooth

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException

/**
 * Frames exchanged between two BlueTalk devices over an RFCOMM link.
 *
 * Wire format: a 4-byte big-endian length prefix followed by that many
 * bytes of UTF-8 encoded JSON. Unknown frame types decode to null so
 * newer versions of the app can add frames without breaking older ones.
 */
sealed interface Frame {
    /**
     * Sent by both sides right after connecting, announcing the display
     * name and (for BLE) an install-stable peer id. RFCOMM peers key
     * conversations by MAC address and ignore [peerId].
     */
    data class Hello(val name: String, val peerId: String = "") : Frame

    /** A chat message. */
    data class Text(val id: String, val body: String, val timestamp: Long) : Frame

    /** Acknowledges that message [id] reached the peer's device. */
    data class Delivered(val id: String) : Frame

    /** The peer opened the conversation and saw these messages. */
    data class Read(val ids: List<String>) : Frame

    /** The peer started or stopped typing. */
    data class Typing(val active: Boolean) : Frame

    /**
     * Announces an incoming file (image or arbitrary attachment). The bytes
     * follow as ordered [FileData] frames and finish with [FileEnd]. Files
     * are transferred in slices because a whole image exceeds one frame.
     */
    data class FileStart(
        val id: String,
        val name: String,
        val mime: String,
        val size: Long,
    ) : Frame

    /** One base64-encoded slice of a file transfer, in order. */
    data class FileData(val id: String, val seq: Int, val data: String) : Frame

    /** Marks a file transfer complete. */
    data class FileEnd(val id: String) : Frame
}

object ChatProtocol {

    /** Upper bound on a single frame, guarding against corrupt length prefixes. */
    const val MAX_FRAME_BYTES: Int = 256 * 1024

    fun encode(frame: Frame): ByteArray {
        val json = JSONObject()
        when (frame) {
            is Frame.Hello -> {
                json.put("type", "hello")
                json.put("name", frame.name)
                json.put("peerId", frame.peerId)
            }
            is Frame.Text -> {
                json.put("type", "msg")
                json.put("id", frame.id)
                json.put("body", frame.body)
                json.put("ts", frame.timestamp)
            }
            is Frame.Delivered -> {
                json.put("type", "delivered")
                json.put("id", frame.id)
            }
            is Frame.Read -> {
                json.put("type", "read")
                json.put("ids", JSONArray(frame.ids))
            }
            is Frame.Typing -> {
                json.put("type", "typing")
                json.put("active", frame.active)
            }
            is Frame.FileStart -> {
                json.put("type", "fileStart")
                json.put("id", frame.id)
                json.put("name", frame.name)
                json.put("mime", frame.mime)
                json.put("size", frame.size)
            }
            is Frame.FileData -> {
                json.put("type", "fileData")
                json.put("id", frame.id)
                json.put("seq", frame.seq)
                json.put("data", frame.data)
            }
            is Frame.FileEnd -> {
                json.put("type", "fileEnd")
                json.put("id", frame.id)
            }
        }
        return json.toString().toByteArray(Charsets.UTF_8)
    }

    /** Returns null for unknown frame types or malformed JSON. */
    fun decode(bytes: ByteArray): Frame? = try {
        val json = JSONObject(String(bytes, Charsets.UTF_8))
        when (json.getString("type")) {
            "hello" -> Frame.Hello(json.getString("name"), json.optString("peerId", ""))
            "msg" -> Frame.Text(json.getString("id"), json.getString("body"), json.getLong("ts"))
            "delivered" -> Frame.Delivered(json.getString("id"))
            "read" -> {
                val array = json.getJSONArray("ids")
                Frame.Read(List(array.length()) { array.getString(it) })
            }
            "typing" -> Frame.Typing(json.getBoolean("active"))
            "fileStart" -> Frame.FileStart(
                json.getString("id"),
                json.getString("name"),
                json.getString("mime"),
                json.getLong("size"),
            )
            "fileData" -> Frame.FileData(json.getString("id"), json.getInt("seq"), json.getString("data"))
            "fileEnd" -> Frame.FileEnd(json.getString("id"))
            else -> null
        }
    } catch (e: JSONException) {
        null
    }

    @Throws(IOException::class)
    fun write(output: DataOutputStream, frame: Frame) {
        val payload = encode(frame)
        output.writeInt(payload.size)
        output.write(payload)
        output.flush()
    }

    /** Blocks until a complete frame arrives. Returns null for unknown frame types. */
    @Throws(IOException::class)
    fun read(input: DataInputStream): Frame? {
        val length = input.readInt()
        if (length <= 0 || length > MAX_FRAME_BYTES) {
            throw IOException("Invalid frame length: $length")
        }
        val payload = ByteArray(length)
        input.readFully(payload)
        return decode(payload)
    }
}
