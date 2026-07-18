# BlueTalk for iOS

SwiftUI + CoreBluetooth implementation of BlueTalk. Same conversations,
bubbles, delivery ticks, typing indicators and offline queueing as the
Android app — but transported over **Bluetooth Low Energy**, because iOS
does not allow third-party apps to use Bluetooth Classic (RFCOMM).
The BLE framing is documented in [`docs/ble-protocol.md`](../docs/ble-protocol.md).

## Building (on your Mac)

The Xcode project file is generated from `project.yml` by
[XcodeGen](https://github.com/yonaskolb/XcodeGen), so there is nothing to
merge-conflict over:

```bash
brew install xcodegen
cd ios
xcodegen generate
open BlueTalk.xcodeproj
```

Then in Xcode:

1. Select the **BlueTalk** target → *Signing & Capabilities* → choose
   your **Team** (your paid developer account).
2. Plug in your iPhone, pick it as the run destination, press **Run**.
3. First launch: accept the Bluetooth permission prompt.

> **Real devices only** — the iOS Simulator has no Bluetooth support, so
> the app must run on hardware to actually connect. (CI builds against
> the simulator SDK purely to type-check the code.)

## Distributing to friends

With the paid account you can upload to **TestFlight** (Xcode →
Product → Archive → Distribute App → TestFlight & App Store), then invite
testers by email or a public link. That's the easiest way to get BlueTalk
onto other people's iPhones without cables.

## Trying it with two iPhones

1. Install BlueTalk on both.
2. Open **＋ (New chat)** on both phones — each phone advertises and
   scans at the same time.
3. Tap the other device when it appears; when the link comes up, the
   conversation appears in the list. Chat away — ticks, typing and read
   receipts work just like the Android version.

## Current interop status

- iPhone ↔ iPhone: **works** (BLE).
- Android ↔ Android: **works** (Bluetooth Classic RFCOMM, or BLE).
- Android ↔ iPhone: **works** (BLE) — the Android app now speaks this same
  GATT service and framing. On Android, pick the device under
  “Nearby devices — works with iPhone”.
