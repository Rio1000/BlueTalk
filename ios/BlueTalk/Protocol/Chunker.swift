import Foundation

/// GATT packets are MTU-limited, so frames travel as chunks:
/// a 1-byte flags header (bit 0 = final chunk) followed by payload bytes.
enum Chunker {
    static let maxFrameBytes = 64 * 1024
    static let finalFlag: UInt8 = 0x01

    static func chunks(for frame: Data, mtu: Int) -> [Data] {
        let payloadSize = max(1, mtu - 1)
        var result: [Data] = []
        var offset = 0
        while offset < frame.count {
            let end = min(offset + payloadSize, frame.count)
            var chunk = Data([end == frame.count ? finalFlag : 0x00])
            chunk.append(frame.subdata(in: offset..<end))
            result.append(chunk)
            offset = end
        }
        if result.isEmpty {
            result = [Data([finalFlag])]
        }
        return result
    }
}

/// Rebuilds frames from a stream of chunks arriving on one link.
final class Reassembler {
    private var buffer = Data()

    /// Returns a complete frame when the final chunk arrives, else nil.
    func ingest(_ chunk: Data) -> Data? {
        guard let flags = chunk.first else { return nil }
        buffer.append(chunk.dropFirst())
        if buffer.count > Chunker.maxFrameBytes {
            buffer.removeAll()
            return nil
        }
        if flags & Chunker.finalFlag != 0 {
            let frame = buffer
            buffer = Data()
            return frame
        }
        return nil
    }
}
