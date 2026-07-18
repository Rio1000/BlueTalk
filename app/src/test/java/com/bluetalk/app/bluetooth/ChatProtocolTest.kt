package com.bluetalk.app.bluetooth

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException

class ChatProtocolTest {

    private fun roundTrip(frame: Frame): Frame? {
        val buffer = ByteArrayOutputStream()
        ChatProtocol.write(DataOutputStream(buffer), frame)
        return ChatProtocol.read(DataInputStream(ByteArrayInputStream(buffer.toByteArray())))
    }

    @Test
    fun `hello round trips`() {
        assertEquals(Frame.Hello("Ada's Pixel"), roundTrip(Frame.Hello("Ada's Pixel")))
    }

    @Test
    fun `text message round trips`() {
        val frame = Frame.Text("id-123", "hello over bluetooth 👋", 1721260800000L)
        assertEquals(frame, roundTrip(frame))
    }

    @Test
    fun `delivered ack round trips`() {
        assertEquals(Frame.Delivered("id-9"), roundTrip(Frame.Delivered("id-9")))
    }

    @Test
    fun `read receipt round trips`() {
        val frame = Frame.Read(listOf("a", "b", "c"))
        assertEquals(frame, roundTrip(frame))
    }

    @Test
    fun `typing round trips`() {
        assertEquals(Frame.Typing(true), roundTrip(Frame.Typing(true)))
        assertEquals(Frame.Typing(false), roundTrip(Frame.Typing(false)))
    }

    @Test
    fun `multiple frames stream back to back`() {
        val buffer = ByteArrayOutputStream()
        val output = DataOutputStream(buffer)
        ChatProtocol.write(output, Frame.Text("1", "first", 1L))
        ChatProtocol.write(output, Frame.Typing(false))
        ChatProtocol.write(output, Frame.Delivered("1"))
        val input = DataInputStream(ByteArrayInputStream(buffer.toByteArray()))
        assertEquals(Frame.Text("1", "first", 1L), ChatProtocol.read(input))
        assertEquals(Frame.Typing(false), ChatProtocol.read(input))
        assertEquals(Frame.Delivered("1"), ChatProtocol.read(input))
    }

    @Test
    fun `unknown frame type decodes to null`() {
        assertNull(ChatProtocol.decode("""{"type":"videocall"}""".toByteArray()))
    }

    @Test
    fun `malformed json decodes to null`() {
        assertNull(ChatProtocol.decode("not json at all".toByteArray()))
    }

    @Test
    fun `oversized length prefix is rejected`() {
        val buffer = ByteArrayOutputStream()
        DataOutputStream(buffer).writeInt(ChatProtocol.MAX_FRAME_BYTES + 1)
        val input = DataInputStream(ByteArrayInputStream(buffer.toByteArray()))
        assertThrows(IOException::class.java) { ChatProtocol.read(input) }
    }

    @Test
    fun `negative length prefix is rejected`() {
        val buffer = ByteArrayOutputStream()
        DataOutputStream(buffer).writeInt(-5)
        val input = DataInputStream(ByteArrayInputStream(buffer.toByteArray()))
        assertThrows(IOException::class.java) { ChatProtocol.read(input) }
    }
}
