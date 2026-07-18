import Foundation

/// Chat frames exchanged between BlueTalk devices. The JSON field names
/// match the Android app exactly so the two platforms interoperate.
enum Frame: Equatable {
    case hello(name: String, peerId: String)
    case text(id: String, body: String, timestampMillis: Int64)
    case delivered(id: String)
    case read(ids: [String])
    case typing(active: Bool)

    func encoded() -> Data {
        var json: [String: Any] = [:]
        switch self {
        case .hello(let name, let peerId):
            json["type"] = "hello"
            json["name"] = name
            json["peerId"] = peerId
        case .text(let id, let body, let timestampMillis):
            json["type"] = "msg"
            json["id"] = id
            json["body"] = body
            json["ts"] = timestampMillis
        case .delivered(let id):
            json["type"] = "delivered"
            json["id"] = id
        case .read(let ids):
            json["type"] = "read"
            json["ids"] = ids
        case .typing(let active):
            json["type"] = "typing"
            json["active"] = active
        }
        return (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
    }

    /// Returns nil for malformed payloads or unknown frame types, so newer
    /// app versions can add frames without breaking older ones.
    static func decode(_ data: Data) -> Frame? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any],
              let type = json["type"] as? String
        else { return nil }

        switch type {
        case "hello":
            guard let name = json["name"] as? String else { return nil }
            let peerId = json["peerId"] as? String ?? ""
            return .hello(name: name, peerId: peerId)
        case "msg":
            guard let id = json["id"] as? String,
                  let body = json["body"] as? String,
                  let ts = json["ts"] as? NSNumber
            else { return nil }
            return .text(id: id, body: body, timestampMillis: ts.int64Value)
        case "delivered":
            guard let id = json["id"] as? String else { return nil }
            return .delivered(id: id)
        case "read":
            guard let ids = json["ids"] as? [String] else { return nil }
            return .read(ids: ids)
        case "typing":
            guard let active = json["active"] as? Bool else { return nil }
            return .typing(active: active)
        default:
            return nil
        }
    }
}
