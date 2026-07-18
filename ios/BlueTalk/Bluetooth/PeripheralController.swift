import CoreBluetooth
import Foundation

/// The "server" half of the transport: advertises the BlueTalk service,
/// receives frames as writes to the RX characteristic and pushes frames
/// to subscribed centrals as TX notifications.
final class PeripheralController: NSObject {

    weak var delegate: LinkEventDelegate?

    private let queue = DispatchQueue(label: "bluetalk.peripheral")
    private var manager: CBPeripheralManager!
    private var txCharacteristic: CBMutableCharacteristic?

    private var localName: String
    private var serviceAdded = false

    private var centrals: [UUID: CBCentral] = [:]
    private var reassemblers: [UUID: Reassembler] = [:]
    /// Chunks waiting for the notification queue to drain, per central.
    private var backlog: [UUID: [Data]] = [:]

    init(localName: String) {
        self.localName = localName
        super.init()
        manager = CBPeripheralManager(
            delegate: self,
            queue: queue,
            options: [CBPeripheralManagerOptionRestoreIdentifierKey: "bluetalk.peripheral"]
        )
    }

    /// Restarts advertising under a new display name.
    func updateLocalName(_ name: String) {
        queue.async { [self] in
            localName = name
            guard manager.state == .poweredOn else { return }
            manager.stopAdvertising()
            startAdvertising()
        }
    }

    private func startAdvertising() {
        manager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [BleConstants.service],
            CBAdvertisementDataLocalNameKey: localName,
        ])
    }

    private func setUpService() {
        guard !serviceAdded else {
            startAdvertising()
            return
        }
        let tx = CBMutableCharacteristic(
            type: BleConstants.txCharacteristic,
            properties: [.notify],
            value: nil,
            permissions: [.readable]
        )
        let rx = CBMutableCharacteristic(
            type: BleConstants.rxCharacteristic,
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )
        let service = CBMutableService(type: BleConstants.service, primary: true)
        service.characteristics = [tx, rx]
        txCharacteristic = tx
        manager.add(service)
        serviceAdded = true
    }

    private func send(_ frame: Data, to centralId: UUID) {
        queue.async { [self] in
            guard let central = centrals[centralId] else { return }
            var mtu = central.maximumUpdateValueLength
            if mtu <= 1 { mtu = BleConstants.fallbackMtu }
            backlog[centralId, default: []].append(contentsOf: Chunker.chunks(for: frame, mtu: mtu))
            drainBacklog(for: centralId)
        }
    }

    private func drainBacklog(for centralId: UUID) {
        guard let tx = txCharacteristic, let central = centrals[centralId] else { return }
        while let chunk = backlog[centralId]?.first {
            let accepted = manager.updateValue(chunk, for: tx, onSubscribedCentrals: [central])
            if !accepted {
                // Queue is full; peripheralManagerIsReady will resume.
                return
            }
            backlog[centralId]?.removeFirst()
        }
    }

    private func teardown(centralId: UUID) {
        centrals[centralId] = nil
        reassemblers[centralId] = nil
        backlog[centralId] = nil
        DispatchQueue.main.async { self.delegate?.linkDown(linkId: centralId) }
    }
}

extension PeripheralController: CBPeripheralManagerDelegate {

    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        // iOS restores the advertising state and service; re-register if needed.
        if dict[CBPeripheralManagerRestoredStateServicesKey] != nil {
            serviceAdded = true
        }
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            setUpService()
        } else {
            for centralId in Array(centrals.keys) {
                teardown(centralId: centralId)
            }
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didAdd service: CBService,
        error: Error?
    ) {
        if error == nil {
            startAdvertising()
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        guard characteristic.uuid == BleConstants.txCharacteristic else { return }
        let id = central.identifier
        centrals[id] = central
        reassemblers[id] = Reassembler()
        DispatchQueue.main.async {
            self.delegate?.linkUp(
                linkId: id,
                send: { [weak self] frame in self?.send(frame, to: id) },
                close: { [weak self] in self?.queue.async { self?.teardown(centralId: id) } }
            )
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        guard characteristic.uuid == BleConstants.txCharacteristic else { return }
        teardown(centralId: central.identifier)
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didReceiveWrite requests: [CBATTRequest]
    ) {
        for request in requests where request.characteristic.uuid == BleConstants.rxCharacteristic {
            guard let chunk = request.value else { continue }
            let centralId = request.central.identifier
            let reassembler: Reassembler
            if let existing = reassemblers[centralId] {
                reassembler = existing
            } else {
                reassembler = Reassembler()
                reassemblers[centralId] = reassembler
            }
            if let frame = reassembler.ingest(chunk) {
                DispatchQueue.main.async {
                    self.delegate?.frameReceived(linkId: centralId, frame: frame)
                }
            }
        }
        if let first = requests.first, first.characteristic.properties.contains(.write) {
            peripheral.respond(to: first, withResult: .success)
        }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        for centralId in Array(backlog.keys) {
            drainBacklog(for: centralId)
        }
    }
}
