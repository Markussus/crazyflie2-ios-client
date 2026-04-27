//
//  BluetoothLink.swift
//  Bluetooth connection to Crazyflie
//    Sends and receives CRTP packet to/from Crazyflie firmware and bootloader
//
//  Created by Arnaud Taffanel on 22/04/15.
//  Copyright (c) 2015 Bitcraze. All rights reserved.
//

import Foundation
import CoreBluetooth
/**
    Bluetooth connection link to a Crazyflie 2.X

    This class implements all logic to send and receive packet to and from the
    Crazyflie 2.X. Documentation for the BTLE protocol can be found on the
    Bitcraze Wiki: https://www.bitcraze.io/documentation/repository/crazyflie2-nrf-firmware/master/protocols/ble
 */
final class BluetoothLink : NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    struct DiscoveredCrazyflie {
        let identifier: UUID
        let name: String
        let rssi: Int
        let isReadyToPair: Bool
        let isConnected: Bool
    }

    private struct DiscoveredPeripheral {
        let peripheral: CBPeripheral
        var name: String
        var rssi: Int
        var isReadyToPair: Bool
    }
    
    let crazyflieServiceUuid = "00000201-1C7F-4F9E-947B-43B7C00A9A08"
    let crtpCharacteristicUuid = "00000202-1C7F-4F9E-947B-43B7C00A9A08"
    let crtpUpCharacteristicUuid = "00000203-1C7F-4F9E-947B-43B7C00A9A08"
    let crtpDownCharacteristicUuid = "00000204-1C7F-4F9E-947B-43B7C00A9A08"
    
    // Structure that decodes and encodes crtpUp and crtpDown control byte (header)
    // For format see https://www.bitcraze.io/documentation/repository/crazyflie2-nrf-firmware/master/protocols/ble#characteristics
    struct ControlByte {
        var start: Bool { (raw & 0x80) != 0 }
        var pid: Int { Int((raw & 0b0110_0000) >> 5) }
        var length: Int { Int(raw & 0b0001_1111) + 1 }
        
        let raw: UInt8

        init(_ raw: UInt8) {
            self.raw = raw
        }

        init(start: Bool, pid: Int, length: Int) {
            self.raw = (start ? 0x80 : 0x00) | UInt8((pid & 0x03) << 5) | UInt8(((length - 1) & 0x1f))
        }
    }
    
    var canBluetooth = false
    
    var stateCallback: ((NSString) -> ())?
    var txCallback: ((Bool) -> ())?
    var rxCallback: ((Data) -> ())?
    var discoveryCallback: (([DiscoveredCrazyflie], Bool) -> ())?
    private(set) var connectedName: String?
    
    fileprivate var centralManager: CBCentralManager?
    fileprivate var peripheralBLE: CBPeripheral?
    fileprivate var connectingPeripheral: CBPeripheral?
    fileprivate var crazyflie: CBPeripheral?
    fileprivate var crtpCharacteristic: CBCharacteristic! = nil
    fileprivate var crtpUpCharacteristic:CBCharacteristic! = nil
    fileprivate var crtpDownCharacteristic:CBCharacteristic! = nil
    
    fileprivate var btQueue: DispatchQueue
    fileprivate var pollTimer: Timer?
    
    
    fileprivate var state = "idle" {
        didSet {
            stateCallback?(state as NSString)
        }
    }
    fileprivate var error = ""
    
    fileprivate var scanTimer: Timer?
    fileprivate var discoveryTimer: Timer?
    
    fileprivate var connectCallback: ((Bool) -> ())?
    
    fileprivate var address = "Crazyflie"
    fileprivate var targetIdentifier: UUID?
    fileprivate var isDiscoveringNearbyDevices = false
    private var discoveredPeripherals: [UUID: DiscoveredPeripheral] = [:]
    
    override init() {
        self.btQueue = DispatchQueue(label: "se.bitcraze.crazyfliecontrol.bluetooth", attributes: [])
        
        super.init()
        
        centralManager = CBCentralManager(delegate: self, queue: nil)
        if #available(iOS 10.0, *) {
            canBluetooth = centralManager!.state == CBManagerState.poweredOn
        } else {
            canBluetooth = centralManager!.state.rawValue == 5 // PoweredOn
        }
        
        state = "idle"
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if #available(iOS 10.0, *) {
            canBluetooth = central.state == CBManagerState.poweredOn
        } else {
            canBluetooth = central.state.rawValue == 5 // PoweredOn
        }
        print("Bluetooth is now " + (canBluetooth ? "on" : "off"))

        if canBluetooth {
            refreshAvailableDevices()
        } else {
            stopNearbyDiscovery(resetDevices: true)
        }
    }
    
    func connect(_ address: String?, callback: @escaping (Bool) -> ()) {
        connect(address: address, identifier: nil, callback: callback)
    }

    func connect(address: String?, identifier: UUID?, callback: @escaping (Bool) -> ()) {
        if !canBluetooth || state != "idle" {
            error = canBluetooth ? "Already connected":"Bluetooth disabled"
            callback(false)
            return
        }
        
        if address == nil {
            self.address = "Crazyflie"
        } else {
            self.address = address!
        }
        self.targetIdentifier = identifier
        
        // Reseting characteristics
        self.crtpCharacteristic = nil
        self.crtpUpCharacteristic = nil
        self.crtpDownCharacteristic = nil
        
        
        if let central = centralManager {
            connectCallback = callback
            stopNearbyDiscovery(resetDevices: false)

            if let identifier = identifier,
               let discoveredPeripheral = discoveredPeripherals[identifier] {
                NSLog("Connecting to discovered peripheral \(discoveredPeripheral.name)")
                connectingPeripheral = discoveredPeripheral.peripheral
                state = "connecting"
                central.connect(discoveredPeripheral.peripheral, options: nil)
                return
            }

            let connectedPeripheral = central.retrieveConnectedPeripherals(withServices: [CBUUID(string: crazyflieServiceUuid)])
            
            if let peripheral = connectedPeripheral.first(where: { matchesSelection(peripheral: $0, fallbackName: $0.name) }) {
                NSLog("Already connected, reusing peripheral")
                connectingPeripheral = peripheral
                central.connect(connectingPeripheral!, options: nil)
                state = "connecting"
            } else {
                NSLog("Start scanning")
                central.scanForPeripherals(withServices: [CBUUID(string: crazyflieServiceUuid)], options: nil)
                state = "scanning"
                
                scanTimer = Timer.scheduledTimer(timeInterval: 10, target: self, selector: #selector(scanningTimeout), userInfo: nil, repeats: false)
            }
        }
    }

    func refreshAvailableDevices() {
        guard canBluetooth, state == "idle", let central = centralManager else {
            notifyDiscoveryUpdate()
            return
        }

        stopNearbyDiscovery(resetDevices: false)
        isDiscoveringNearbyDevices = true
        central.scanForPeripherals(withServices: [CBUUID(string: crazyflieServiceUuid)],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        discoveryTimer = Timer.scheduledTimer(timeInterval: 4, target: self, selector: #selector(discoveryTimeout), userInfo: nil, repeats: false)
        notifyDiscoveryUpdate()
    }
    
    @objc
    private func scanningTimeout(timer: Timer) {
        NSLog("Scan timeout, stop scan")
        centralManager!.stopScan()
        state = "idle"
        scanTimer?.invalidate()
        scanTimer = nil
        
        error = "Timeout"
        connectCallback?(false)
    }

    @objc
    private func discoveryTimeout(timer: Timer) {
        stopNearbyDiscovery(resetDevices: false)
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let peripheralName = displayName(for: peripheral, advertisementData: advertisementData)
        let isConnectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue
            ?? (advertisementData[CBAdvertisementDataIsConnectable] as? Bool)
            ?? true
        let matchesCrazyflie = matchesCrazyflieName(peripheralName)
            || (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.contains(CBUUID(string: crazyflieServiceUuid)) == true

        if matchesCrazyflie {
            discoveredPeripherals[peripheral.identifier] = DiscoveredPeripheral(peripheral: peripheral,
                                                                                name: peripheralName,
                                                                                rssi: RSSI.intValue,
                                                                                isReadyToPair: isConnectable)
            notifyDiscoveryUpdate()
        }

        if state == "scanning", matchesSelection(peripheral: peripheral, fallbackName: peripheralName) {
            scanTimer?.invalidate()
            scanTimer = nil
            central.stopScan()
            NSLog("Stop scanning")
            connectingPeripheral = peripheral
            state = "connecting"

            central.connect(peripheral, options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        self.error = "Failed to connect"
        state = "idle"
        connectCallback?(false)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        crazyflie = peripheral
        connectedName = peripheral.name
        discoveredPeripherals[peripheral.identifier] = DiscoveredPeripheral(peripheral: peripheral,
                                                                            name: peripheral.name ?? displayName(for: peripheral, advertisementData: [:]),
                                                                            rssi: discoveredPeripherals[peripheral.identifier]?.rssi ?? 0,
                                                                            isReadyToPair: true)
        notifyDiscoveryUpdate()
        
        NSLog("Crazyflie connected, refreshing services ...")
        
        peripheral.delegate = self
        
        peripheral.discoverServices([CBUUID(string: crazyflieServiceUuid)])
        
        state = "services"
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        disconnect()
        
        if let error = error {
            self.error = error.localizedDescription
        }
        
        connectCallback?(false)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else {return }
        
        for service in services {
            if service.uuid.uuidString == crazyflieServiceUuid {
                peripheral.discoverCharacteristics([CBUUID(string: crtpCharacteristicUuid),
                                                    CBUUID(string: crtpUpCharacteristicUuid),
                                                    CBUUID(string: crtpDownCharacteristicUuid)], for: service)
                state = "characteristics"
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics  {
            if characteristic.uuid.uuidString == crtpCharacteristicUuid {
                self.crtpCharacteristic = characteristic
            } else if characteristic.uuid.uuidString == crtpUpCharacteristicUuid {
                self.crtpUpCharacteristic = characteristic
            } else if characteristic.uuid.uuidString == crtpDownCharacteristicUuid {
                self.crtpDownCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
            
            if self.crtpCharacteristic != nil && self.crtpUpCharacteristic != nil && crtpDownCharacteristic != nil {
                state = "connected"
                connectCallback?(true)
                // Start the packet polling
                self.btQueue.async {
                    self.sendAPacket()
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            NSLog("Error setting notification state: " + error.localizedDescription)
            return
        }
        
        NSLog("Changed notification state for " + characteristic.uuid.uuidString)
    }
    
    fileprivate var decoderLength = 0
    fileprivate var decoderPid = -1
    fileprivate var decoderData: [UInt8] = []
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        
        print("Received value for characteristic: \(characteristic.uuid.uuidString), length: \(data.count)")
        
        var dataArray = [UInt8](repeating: 0, count: data.count)
        (data as NSData).getBytes(&dataArray, length: dataArray.count)
        let header = ControlByte(dataArray[0])
        
        if header.start {
            if header.length < 20 {
                self.rxCallback?(Data(dataArray.dropFirst()))
            } else {
                self.decoderData = Array(dataArray[1..<dataArray.count])
                self.decoderPid = header.pid
                self.decoderLength = header.length
            }
        } else {
            if header.pid == self.decoderPid {
                self.rxCallback?(Data(self.decoderData + dataArray.dropFirst()))
            } else {
                self.decoderPid = -1
                self.decoderData = []
                self.decoderLength = 0
                NSLog("Bluetooth link: Error while receiving long data: PID does not match!")
            }
        }
        
    }
    
    var isConnected: Bool {
        return state == "connected"
    }
    
    func disconnect() {
        switch state {
        case "scanning":
            NSLog("Cancel scanning")
            centralManager!.stopScan()
            scanTimer?.invalidate()
        case "connecting", "services", "characteristics", "connected":
            if let peripheral = connectingPeripheral {
                centralManager?.cancelPeripheralConnection(peripheral)
            }
        default:
            break
        }
        
        connectingPeripheral = nil
        crazyflie = nil
        crtpCharacteristic = nil
        connectedName = nil
        targetIdentifier = nil
        
        state = "idle"
        error = "Disconnected"
        print("Connection IDLE")
        notifyDiscoveryUpdate()
    }
    
    func getState() -> NSString {
        return state as NSString
    }
    
    func getError() -> String {
        return error
    }
    
    func onStateUpdated(_ callback: @escaping (NSString) -> ()) {
        stateCallback = callback
    }

    func onPacketReceived(_ callback: @escaping (Data) -> ()) {
        rxCallback = callback
    }

    func onDiscoveredDevices(_ callback: @escaping ([DiscoveredCrazyflie], Bool) -> ()) {
        discoveryCallback = callback
        notifyDiscoveryUpdate()
    }
    
    
    // MARK: Bluetooth queue
    
    // The following variables are modified ONLY from the bluetooth execution queue
    fileprivate var packetQueue: [(Data, ((Bool)->())?)] = []
    
    fileprivate var encodedSecondPacket: Data! = nil
    fileprivate var encoderPid = 0
    
    fileprivate let nullPacket: Data = Data([UInt8(0xff)])
    
    /**
        Send a packet to Crazyflie

        - parameter packet: Packet to send. Should be less than 31Bytes long
        - parameter callback: Callback called when the packet has been sent of not.
                The boolean will be true is the packet has been sent, false otherwise.
    */
    func sendPacket(_ packet: Data, callback: ((Bool) -> ())?) {
        self.btQueue.async {
            self.packetQueue.append((packet, callback))
        }
    }
    
    /* Send either a packet from the packetQueue or a NULL packet */
    fileprivate func sendAPacket() {
        var packet: Data
        var callback: ((Bool)->())?
        
        if packetQueue.count > 0 {
            (packet, callback) = self.packetQueue.removeLast()
        } else {
            packet = self.nullPacket
            callback = nil
        }
        
        if state != "connected" {
            callback?(false)
            return
        }
        
        txCallback = callback
        
        // If the packet is small send it with the simple crtp characteristic, otherwise send it with the segmented crtpUp characteristic
        if packet.count <= 20 {
            self.encodedSecondPacket = nil
            crazyflie!.writeValue(packet, for: crtpCharacteristic, type: CBCharacteristicWriteType.withResponse)
        } else {
            var packetArray = [UInt8](repeating: 0, count: packet.count)
            (packet as NSData).getBytes(&packetArray, length: packetArray.count)
            
            var header: UInt8 = UInt8(ControlByte(start: true, pid: self.encoderPid, length: packet.count).raw)
            let firstPacket = Data(packetArray[0..<19])
            
            header = UInt8(ControlByte(start: false, pid: self.encoderPid, length: 0).raw)
            self.encodedSecondPacket = Data([header] + packetArray[19...])
            
            crazyflie!.writeValue(firstPacket, for: crtpUpCharacteristic, type: CBCharacteristicWriteType.withResponse)
            
            self.encoderPid = (self.encoderPid+1)%4
        }
        
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if self.encodedSecondPacket == nil {
            txCallback?(true)
            self.btQueue.async {
                self.sendAPacket()
            }
        } else {
            crazyflie!.writeValue(self.encodedSecondPacket, for: crtpUpCharacteristic, type: CBCharacteristicWriteType.withResponse)
            self.encodedSecondPacket = nil
        }
    }

    private func stopNearbyDiscovery(resetDevices: Bool) {
        discoveryTimer?.invalidate()
        discoveryTimer = nil

        let shouldStopScan = isDiscoveringNearbyDevices && state == "idle"
        isDiscoveringNearbyDevices = false

        if shouldStopScan {
            centralManager?.stopScan()
        }

        if resetDevices {
            discoveredPeripherals.removeAll()
        }

        notifyDiscoveryUpdate()
    }

    private func notifyDiscoveryUpdate() {
        let connectedIdentifier = crazyflie?.identifier
        let devices = discoveredPeripherals.values.map { discoveredPeripheral in
            DiscoveredCrazyflie(identifier: discoveredPeripheral.peripheral.identifier,
                                name: discoveredPeripheral.name,
                                rssi: discoveredPeripheral.rssi,
                                isReadyToPair: discoveredPeripheral.isReadyToPair,
                                isConnected: connectedIdentifier.map { $0 == discoveredPeripheral.peripheral.identifier } ?? false)
        }.sorted { lhs, rhs in
            if lhs.isConnected != rhs.isConnected {
                return lhs.isConnected
            }

            if lhs.isReadyToPair != rhs.isReadyToPair {
                return lhs.isReadyToPair
            }

            if lhs.rssi != rhs.rssi {
                return lhs.rssi > rhs.rssi
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        discoveryCallback?(devices, isDiscoveringNearbyDevices)
    }

    private func displayName(for peripheral: CBPeripheral, advertisementData: [String: Any]) -> String {
        if let name = peripheral.name, !name.isEmpty {
            return name
        }

        if let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String,
           !advertisedName.isEmpty {
            return advertisedName
        }

        return "Crazyflie \(peripheral.identifier.uuidString.prefix(4))"
    }

    private func matchesSelection(peripheral: CBPeripheral, fallbackName: String?) -> Bool {
        if let targetIdentifier = targetIdentifier {
            return peripheral.identifier == targetIdentifier
        }

        return (fallbackName ?? peripheral.name ?? "").starts(with: self.address)
    }

    private func matchesCrazyflieName(_ name: String?) -> Bool {
        guard let normalizedName = name?.lowercased(), normalizedName.isEmpty == false else {
            return false
        }

        return normalizedName.contains("crazyflie")
            || normalizedName.contains("cf2")
            || normalizedName.contains("cf21")
            || normalizedName.contains("c21b")
    }
}
