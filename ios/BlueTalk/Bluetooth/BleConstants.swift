import CoreBluetooth

/// GATT identifiers shared with the Android BLE transport
/// (see docs/ble-protocol.md).
enum BleConstants {
    static let service = CBUUID(string: "E5B1A9F4-8C2D-4E6A-9B3F-D7C41E8A2F60")
    /// Central writes chunks here (write with response).
    static let rxCharacteristic = CBUUID(string: "E5B1A9F4-8C2D-4E6A-9B3F-D7C41E8A2F61")
    /// Peripheral notifies chunks here.
    static let txCharacteristic = CBUUID(string: "E5B1A9F4-8C2D-4E6A-9B3F-D7C41E8A2F62")

    /// Conservative fallback when the real ATT payload size is unknown.
    static let fallbackMtu = 180
}

/// A device found while scanning, shown on the Discover screen.
struct DiscoveredPeer: Identifiable, Equatable {
    let id: UUID
    var name: String?
    var rssi: Int
}

/// Events both controllers report to the BluetoothManager. All callbacks
/// are delivered on the main queue.
protocol LinkEventDelegate: AnyObject {
    func linkUp(linkId: UUID, send: @escaping (Data) -> Void, close: @escaping () -> Void)
    func linkDown(linkId: UUID)
    func frameReceived(linkId: UUID, frame: Data)
}
