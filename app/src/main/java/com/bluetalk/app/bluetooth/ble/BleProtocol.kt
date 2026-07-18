package com.bluetalk.app.bluetooth.ble

import java.io.ByteArrayOutputStream
import java.util.UUID

/**
 * GATT identifiers and framing shared with the iOS BLE transport
 * (see docs/ble-protocol.md). Chat frames themselves are the same
 * length-agnostic JSON as the RFCOMM path — only the on-air chunking
 * differs, because GATT packets are MTU-limited.
 */
object BleProtocol {

    val SERVICE_UUID: UUID = UUID.fromString("E5B1A9F4-8C2D-4E6A-9B3F-D7C41E8A2F60")

    /** Central writes frame chunks here (write with response). */
    val RX_UUID: UUID = UUID.fromString("E5B1A9F4-8C2D-4E6A-9B3F-D7C41E8A2F61")

    /** Peripheral notifies frame chunks here. */
    val TX_UUID: UUID = UUID.fromString("E5B1A9F4-8C2D-4E6A-9B3F-D7C41E8A2F62")

    /** Standard Client Characteristic Configuration descriptor. */
    val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    /** Bit 0 of the chunk header marks the final chunk of a frame. */
    const val FINAL_FLAG: Byte = 0x01

    /** Usable ATT payload before an MTU is negotiated (default MTU 23 − 3). */
    const val FALLBACK_PACKET: Int = 20

    /** Guards reassembly against a peer streaming an unbounded frame. */
    const val MAX_FRAME_BYTES: Int = 64 * 1024

    /**
     * Splits a frame into chunks that each fit one ATT packet:
     * a 1-byte header (final-flag) followed by up to [maxPacketBytes] − 1
     * payload bytes.
     */
    fun chunk(frame: ByteArray, maxPacketBytes: Int): List<ByteArray> {
        val payloadSize = (maxPacketBytes - 1).coerceAtLeast(1)
        val chunks = ArrayList<ByteArray>()
        var offset = 0
        while (offset < frame.size) {
            val end = minOf(offset + payloadSize, frame.size)
            val chunk = ByteArray(end - offset + 1)
            chunk[0] = if (end == frame.size) FINAL_FLAG else 0
            System.arraycopy(frame, offset, chunk, 1, end - offset)
            chunks.add(chunk)
            offset = end
        }
        if (chunks.isEmpty()) chunks.add(byteArrayOf(FINAL_FLAG))
        return chunks
    }

    /** Rebuilds frames from the chunk stream arriving on one link. */
    class Reassembler {
        private val buffer = ByteArrayOutputStream()

        /** Returns the frame bytes when the final chunk arrives, else null. */
        fun ingest(chunk: ByteArray): ByteArray? {
            if (chunk.isEmpty()) return null
            buffer.write(chunk, 1, chunk.size - 1)
            if (buffer.size() > MAX_FRAME_BYTES) {
                buffer.reset()
                return null
            }
            return if (chunk[0].toInt() and FINAL_FLAG.toInt() != 0) {
                val frame = buffer.toByteArray()
                buffer.reset()
                frame
            } else {
                null
            }
        }
    }
}
