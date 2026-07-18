import CoreBluetooth
import Foundation

/// The "client" half of the transport: scans for devices advertising the
/// BlueTalk service, connects, writes frames to their RX characteristic
/// and receives frames as TX notifications.
final class CentralController: NSObject {

    weak var delegate: LinkEventDelegate?

    private let queue = DispatchQueue(label: "bluetalk.central")
    private var central: CBCentralManager!

    private var peripherals: [UUID: CBPeripheral] = [:]
    private var rxCharacteristics: [UUID: CBCharacteristic] = [:]
    private var reassemblers: [UUID: Reassembler] = [:]
    private var scanRequested = false

    private(set) var onDiscovery: (DiscoveredPeer) -> Void
    private(set) var onScanState: (Bool) -> Void

    init(
        onDiscovery: @escaping (DiscoveredPeer) -> Void,
        onScanState: @escaping (Bool) -> Void
    ) {
        self.onDiscovery = onDiscovery
        self.onScanState = onScanState
        super.init()
        central = CBCentralManager(delegate: self, queue: queue)
    }

    func startScan() {
        queue.async { [self] in
            scanRequested = true
            beginScanIfReady()
        }
    }

    func stopScan() {
        queue.async { [self] in
            scanRequested = false
            central.stopScan()
            DispatchQueue.main.async { self.onScanState(false) }
        }
    }

    func connect(to id: UUID) {
        queue.async { [self] in
            guard let peripheral = peripherals[id] else { return }
            central.connect(peripheral)
        }
    }

    func disconnect(_ id: UUID) {
        queue.async { [self] in
            guard let peripheral = peripherals[id] else { return }
            central.cancelPeripheralConnection(peripheral)
        }
    }

    private func beginScanIfReady() {
        guard scanRequested, central.state == .poweredOn else { return }
        central.scanForPeripherals(
            withServices: [BleConstants.service],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        DispatchQueue.main.async { self.onScanState(true) }
    }

    private func send(_ frame: Data, to peripheral: CBPeripheral) {
        queue.async { [self] in
            guard let rx = rxCharacteristics[peripheral.identifier] else { return }
            var mtu = peripheral.maximumWriteValueLength(for: .withResponse)
            if mtu <= 1 { mtu = BleConstants.fallbackMtu }
            for chunk in Chunker.chunks(for: frame, mtu: mtu) {
                peripheral.writeValue(chunk, for: rx, type: .withResponse)
            }
        }
    }

    private func teardown(_ peripheral: CBPeripheral) {
        let id = peripheral.identifier
        if rxCharacteristics.removeValue(forKey: id) != nil {
            DispatchQueue.main.async { self.delegate?.linkDown(linkId: id) }
        }
        reassemblers[id] = nil
    }
}

extension CentralController: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            beginScanIfReady()
        } else {
            for peripheral in peripherals.values {
                teardown(peripheral)
            }
            DispatchQueue.main.async { self.onScanState(false) }
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        peripherals[peripheral.identifier] = peripheral
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? peripheral.name
        let peer = DiscoveredPeer(id: peripheral.identifier, name: name, rssi: RSSI.intValue)
        DispatchQueue.main.async { self.onDiscovery(peer) }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([BleConstants.service])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        teardown(peripheral)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        teardown(peripheral)
    }
}

extension CentralController: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == BleConstants.service })
        else { return }
        peripheral.discoverCharacteristics(
            [BleConstants.rxCharacteristic, BleConstants.txCharacteristic],
            for: service
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == BleConstants.rxCharacteristic {
                rxCharacteristics[peripheral.identifier] = characteristic
            } else if characteristic.uuid == BleConstants.txCharacteristic {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == BleConstants.txCharacteristic,
              characteristic.isNotifying,
              rxCharacteristics[peripheral.identifier] != nil
        else { return }
        reassemblers[peripheral.identifier] = Reassembler()
        let id = peripheral.identifier
        DispatchQueue.main.async {
            self.delegate?.linkUp(
                linkId: id,
                send: { [weak self, weak peripheral] frame in
                    guard let self, let peripheral else { return }
                    self.send(frame, to: peripheral)
                },
                close: { [weak self] in self?.disconnect(id) }
            )
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == BleConstants.txCharacteristic,
              let chunk = characteristic.value,
              let frame = reassemblers[peripheral.identifier]?.ingest(chunk)
        else { return }
        let id = peripheral.identifier
        DispatchQueue.main.async {
            self.delegate?.frameReceived(linkId: id, frame: frame)
        }
    }
}
