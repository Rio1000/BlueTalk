# BlueTalk 💬📶

A WhatsApp / iMessage-style messenger for Android that sends and delivers
messages over **Bluetooth** instead of cellular data or Wi-Fi. No servers,
no SIM card, no internet — messages travel directly between phones.

## Features

- **Familiar chat UI** — conversation list with previews and unread badges,
  chat bubbles, timestamps, and a Material 3 look (dynamic color on
  Android 12+).
- **Delivery states like the big messengers** — 🕓 queued, ✓ sent,
  ✓✓ delivered, ✓✓ (blue) read.
- **Read receipts & typing indicators** — see when your contact is typing
  and when they've read your message.
- **Offline queueing** — messages you write while a contact is out of range
  are stored and delivered automatically the next time you connect.
- **Message history** — all conversations are persisted locally in a Room
  database.
- **Background delivery** — a foreground service keeps listening while the
  app is in the background and raises notifications for new messages.
- **Device discovery** — find nearby phones, or become discoverable so a
  friend can find you. Android's standard pairing flow secures the link.

## How it works

BlueTalk uses **Bluetooth Classic (RFCOMM)** — the same reliable,
stream-oriented transport used for wireless serial connections — rather
than the internet:

1. Every device runs an RFCOMM *server socket* registered under a
   BlueTalk-specific SDP service UUID, accepting connections from other
   BlueTalk phones.
2. Opening a chat (or sending while disconnected) creates an outgoing
   RFCOMM connection to the peer.
3. Both sides exchange frames: a 4-byte big-endian length prefix followed
   by a UTF-8 JSON payload.

| Frame       | Payload                       | Purpose                          |
| ----------- | ----------------------------- | -------------------------------- |
| `hello`     | `name`                        | Announce display name on connect |
| `msg`       | `id`, `body`, `ts`            | A chat message                   |
| `delivered` | `id`                          | Ack: message reached the device  |
| `read`      | `ids[]`                       | Read receipt for a set of ids    |
| `typing`    | `active`                      | Typing indicator on/off          |

Messages are identified by sender-generated UUIDs, so re-sending after a
lost acknowledgement never duplicates a message. Status transitions are
monotonic (`pending → sent → delivered → read`) — a late ack can never
downgrade a read message.

Pairing is handled by Android; paired RFCOMM links use standard Bluetooth
link-layer encryption. (End-to-end encryption on top of the link is on the
roadmap.)

## Project layout

```
app/src/main/java/com/bluetalk/app/
├── BlueTalkApp.kt            # Application + dependency container
├── MainActivity.kt           # Permission gate + navigation
├── bluetooth/
│   ├── ChatProtocol.kt       # Wire format: length-prefixed JSON frames
│   ├── ConnectionManager.kt  # RFCOMM server, connections, queue flushing
│   ├── DeviceDiscovery.kt    # Paired devices + classic discovery scan
│   └── ChatService.kt        # Foreground service + notifications
├── data/                     # Room: entities, DAOs, repository
├── settings/                 # Display-name preference store
└── ui/                       # Compose screens: conversations, chat,
                              # discover, settings + view models
```

## Building

Requirements: JDK 17+ and the Android SDK (Android Studio installs both).

```bash
./gradlew assembleDebug        # APK at app/build/outputs/apk/debug/
./gradlew testDebugUnitTest    # protocol unit tests
```

Or open the project in Android Studio and press Run. Every push also
builds the APK on GitHub Actions — grab it from the workflow run's
`bluetalk-debug-apk` artifact.

- **minSdk 26** (Android 8.0), **targetSdk 34**.
- Runs on real devices; emulators generally don't support Bluetooth.

## Trying it with two phones

1. Install BlueTalk on both phones and grant the Bluetooth permissions.
2. On phone A: **New chat → Make me visible**.
3. On phone B: **New chat → Scan**, then tap phone A when it appears and
   confirm the pairing dialog on both phones.
4. Chat! Walk out of range and keep typing — your messages queue and
   deliver when you're back in range (open the chat or tap **Connect**
   to re-establish the link).

## Permissions

| Permission | Why |
| ---------- | --- |
| `BLUETOOTH_CONNECT` / `BLUETOOTH_SCAN` (Android 12+) | Connect to and discover nearby devices |
| `BLUETOOTH`, `BLUETOOTH_ADMIN`, `ACCESS_FINE_LOCATION` (Android 11 and below) | Legacy equivalents; location is required by Android for classic discovery |
| `POST_NOTIFICATIONS` | Message notifications |
| `FOREGROUND_SERVICE_CONNECTED_DEVICE` | Keep receiving messages in the background |

## Limitations & roadmap

- **Range** — Bluetooth Classic reaches roughly 10–30 m depending on the
  hardware and environment.
- **1:1 chats** — group chats and multi-hop mesh relaying (BLE) are
  natural next steps.
- **End-to-end encryption** — links are protected by Bluetooth pairing
  encryption today; an app-layer Noise/X25519 handshake is planned.
- **Text only** — image/file transfer fits the existing framing and is
  planned.
