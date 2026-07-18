# BlueTalk BLE transport (v1)

Bluetooth Classic RFCOMM (used by Android↔Android) is not available to
iOS apps, so cross-platform links use Bluetooth Low Energy. The chat
frames are identical to the RFCOMM ones — only the transport differs.

## GATT layout

Every device plays **both roles at once**: it advertises the BlueTalk
service (peripheral) and scans for it (central).

| UUID | Role |
| ---- | ---- |
| `E5B1A9F4-8C2D-4E6A-9B3F-D7C41E8A2F60` | BlueTalk service |
| `E5B1A9F4-8C2D-4E6A-9B3F-D7C41E8A2F61` | RX characteristic — central **writes** frames to the peripheral (write with response) |
| `E5B1A9F4-8C2D-4E6A-9B3F-D7C41E8A2F62` | TX characteristic — peripheral **notifies** frames to the central |

A link is one GATT connection: the central writes chunks to RX and
subscribes to TX for the peripheral's chunks.

## Chunking

GATT packets are MTU-limited, so each frame is split into chunks:

```
[flags: 1 byte][chunk payload]
```

- `flags & 0x01` — this is the **final** chunk of the frame.
- Receiver concatenates payloads until a final chunk, then decodes the
  reassembled bytes as one JSON frame (same JSON as the RFCOMM path).
- Maximum reassembled frame size: 64 KiB; larger input resets the buffer.

## Identity

BLE MAC addresses are randomized (and hidden entirely on iOS), so links
cannot be keyed by address. Instead every install generates a stable
random **peer id** (UUID string) announced in the `hello` frame:

```json
{"type": "hello", "name": "Ada's iPhone", "peerId": "6de0…"}
```

Conversations over BLE are keyed by `peerId`. All other frames
(`msg`, `delivered`, `read`, `typing`) are unchanged from the RFCOMM
protocol described in the top-level README.

## Notes

- Both sides may connect to each other simultaneously (each is central
  to the other's peripheral); duplicate delivery is harmless because
  message ids de-duplicate on insert.
- iOS advertises only in the "overflow area" while backgrounded, so
  discovery works best with the app in the foreground; established
  links keep working in the background.
