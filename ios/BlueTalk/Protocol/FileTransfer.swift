import Foundation
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

/// A file stored locally, ready to attach to a message or render.
struct FileAttachment {
    let path: String
    let name: String
    let mime: String
}

/// Moves files between devices over the chat channel, matching the Android
/// side: a file is sent as a `fileStart`, ordered `fileData` slices, and a
/// `fileEnd`, and streamed straight to disk on receipt. Outgoing images are
/// downscaled and re-encoded so a photo doesn't crawl over Bluetooth.
///
/// All calls happen on the main thread (the Bluetooth controllers deliver
/// their callbacks there), so no additional locking is needed.
final class FileTransfer {

    private let dir: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = documents.appendingPathComponent("attachments")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private struct Partial {
        let name: String
        let mime: String
        let url: URL
        let handle: FileHandle
    }

    private var partials: [String: Partial] = [:]

    // MARK: - Receiving

    func startIncoming(id: String, name: String, mime: String) {
        let url = dir.appendingPathComponent("\(id)-\(sanitized(name))")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        partials[id] = Partial(name: name, mime: mime, url: url, handle: handle)
    }

    func appendIncoming(id: String, base64: String) {
        guard let partial = partials[id], let data = Data(base64Encoded: base64) else { return }
        try? partial.handle.write(contentsOf: data)
    }

    func finishIncoming(id: String) -> FileAttachment? {
        guard let partial = partials.removeValue(forKey: id) else { return nil }
        try? partial.handle.close()
        return FileAttachment(path: partial.url.path, name: partial.name, mime: partial.mime)
    }

    func abortIncoming(id: String) {
        guard let partial = partials.removeValue(forKey: id) else { return }
        try? partial.handle.close()
        try? FileManager.default.removeItem(at: partial.url)
    }

    // MARK: - Sending

    /// Copies a picked file into app storage, downscaling and recompressing
    /// images. Returns nil if the file can't be read.
    func importOutgoing(from url: URL) -> FileAttachment? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let id = UUID().uuidString
        let mime = mimeType(for: url)
        let name = url.lastPathComponent

        #if canImport(UIKit)
        if mime.hasPrefix("image/"),
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data),
           let jpeg = downscale(image, max: 1280).jpegData(compressionQuality: 0.8) {
            let base = sanitized((name as NSString).deletingPathExtension)
            let dest = dir.appendingPathComponent("\(id)-\(base).jpg")
            guard (try? jpeg.write(to: dest)) != nil else { return nil }
            return FileAttachment(path: dest.path, name: dest.lastPathComponent, mime: "image/jpeg")
        }
        #endif

        let dest = dir.appendingPathComponent("\(id)-\(sanitized(name))")
        do {
            try FileManager.default.copyItem(at: url, to: dest)
        } catch {
            return nil
        }
        return FileAttachment(path: dest.path, name: name, mime: mime)
    }

    /// Streams a file to a peer as protocol frames, passing each to `send`.
    func sendFile(path: String, name: String, mime: String, id: String, send: (Frame) -> Void) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { try? handle.close() }
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attributes?[.size] as? Int) ?? 0
        send(.fileStart(id: id, name: name, mime: mime, size: Int64(size)))
        var seq = 0
        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            send(.fileData(id: id, seq: seq, data: chunk.base64EncodedString()))
            seq += 1
        }
        send(.fileEnd(id: id))
    }

    // MARK: - Helpers

    private func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension),
           let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }

    #if canImport(UIKit)
    private func downscale(_ image: UIImage, max: CGFloat) -> UIImage {
        let width = image.size.width
        let height = image.size.height
        if width <= max && height <= max { return image }
        let ratio = min(max / width, max / height)
        let newSize = CGSize(width: width * ratio, height: height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
    #endif

    private func sanitized(_ name: String) -> String {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        let cleaned = String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        let trimmed = String(cleaned.prefix(80))
        return trimmed.isEmpty ? "file" : trimmed
    }

    private let chunkSize = 8 * 1024
}
