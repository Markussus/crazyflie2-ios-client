//
//  CrazyFlie.swift
//  Crazyflie client
//
//  Created by Martin Eberl on 15.07.16.
//  Copyright (c) 2016 Bitcraze. All rights reserved.
//

import UIKit

protocol CrazyFlieCommander {
    var pitch: Float { get }
    var roll: Float { get }
    var thrust: Float { get }
    var yaw: Float { get }

    func prepareData()
}

enum CrazyFlieHeader: UInt8 {
    case commander = 0x30
}

enum CrazyFlieArmingState {
    case unavailable, disarmed, arming, armed, disarming
}

enum CrazyFlieState {
    case idle, connected , scanning, connecting, services, characteristics
}

protocol CrazyFlieDelegate {
    func didSend()
    func didUpdate(state: CrazyFlieState)
    func didUpdateFlightStatus()
    func didFail(with title: String, message: String?)
}

open class CrazyFlie: NSObject {
    private enum CRTP {
        static let legacySupervisorHeader = header(port: 9, channel: 1)
        static let platformCommandHeader = header(port: 13, channel: 0)
        static let platformVersionHeader = header(port: 13, channel: 1)

        static let armSystemCommand: UInt8 = 1
        static let getDeviceTypeNameCommand: UInt8 = 2
        static let brushlessDeviceType = "C21B"

        static func header(port: UInt8, channel: UInt8) -> UInt8 {
            return (port << 4) | (channel & 0x03)
        }
    }

    private(set) var state:CrazyFlieState {
        didSet {
            delegate?.didUpdate(state: state)
        }
    }
    private(set) var detectedDeviceType: String?
    private(set) var requiresArming = false
    private(set) var armingState: CrazyFlieArmingState = .unavailable
    private(set) var isDetectingDeviceType = false
    private(set) var isDemoMode = false
    private(set) var debugLogText = "Debug log ready."

    private var timer:Timer?
    private var delegate: CrazyFlieDelegate?
    private(set) var bluetoothLink:BluetoothLink!
    private var detectionTimeoutWorkItem: DispatchWorkItem?
    private var armingTimeoutWorkItem: DispatchWorkItem?
    private var pendingArmingTarget: Bool?
    private var hasSentZeroThrustPacket = false
    private var debugLogLines = ["Debug log ready."]
    private var lastCommanderLogSignature: String?

    var commander: CrazyFlieCommander?

    init(bluetoothLink:BluetoothLink? = BluetoothLink(), delegate: CrazyFlieDelegate?) {

        state = .idle
        self.delegate = delegate

        self.bluetoothLink = bluetoothLink
        super.init()

        bluetoothLink?.onStateUpdated { [weak self] (state) in
            guard let self = self else { return }
            switch state {
            case "idle":
                self.state = .idle
            case "connected":
                self.state = .connected
            case "scanning":
                self.state = .scanning
            case "connecting":
                self.state = .connecting
            case "services":
                self.state = .services
            case "characteristics":
                self.state = .characteristics
            default:
                break
            }
        }

        bluetoothLink?.onPacketReceived { [weak self] packet in
            self?.handleIncomingPacket(packet)
        }
    }

    func connect(_ callback:((Bool) -> Void)?) {
        guard state == .idle else {
            self.disconnect()
            return
        }

        appendDebugLog("Connecting over BLE...")

        self.bluetoothLink.connect(nil, callback: {[weak self] (connected) in
            callback?(connected)
            guard connected else {
                if self?.timer != nil {
                    self?.timer?.invalidate()
                    self?.timer = nil
                }

                var title:String
                var body:String?

                // Find the reason and prepare a message
                if self?.bluetoothLink.getError() == "Bluetooth disabled" {
                    title = "Bluetooth disabled"
                    body = "Please enable Bluetooth to connect a Crazyflie"
                } else if self?.bluetoothLink.getError() == "Timeout" {
                    title = "Connection timeout"
                    body = "Could not find Crazyflie"
                } else if self?.bluetoothLink.getError() == "Disconnected" {
                    // Disconnected request, this is not an error
                    return
                } else {
                    title = "Error"
                    body = self?.bluetoothLink.getError()
                }

                self?.delegate?.didFail(with: title, message: body)
                return
            }

            self?.appendDebugLog("BLE connected.")
            self?.requestDeviceType()
            self?.prepareFlightStateForConnectedDevice()
            self?.startTimer()
        })
    }

    func toggleDemoSession() {
        if isDemoMode {
            disconnect()
            return
        }

        guard state == .idle else {
            appendDebugLog("Demo mode blocked: disconnect the current Crazyflie first.")
            return
        }

        resetFlightState()
        isDemoMode = true
        state = .connected
        setFlightRequirement(true, deviceType: "Demo Brushless")
        appendDebugLog("Demo connected: Crazyflie 2.1 Brushless (simulated)")
        startTimer()
    }

    func disconnect() {
        if isDemoMode {
            stopTimer()
            resetFlightState()
            state = .idle
            appendDebugLog("Demo disconnected.")
            return
        }

        bluetoothLink.disconnect()
        stopTimer()
        resetFlightState()
        appendDebugLog("Disconnected.")
        delegate?.didUpdateFlightStatus()
    }

    func toggleArm() {
        guard state == .connected else {
            return
        }

        if !requiresArming {
            setFlightRequirement(true, deviceType: detectedDeviceType)
        }

        switch armingState {
        case .disarmed:
            requestArming(true)
        case .armed:
            requestArming(false)
        case .unavailable:
            requestArming(true)
        default:
            break
        }
    }

    func disarmIfNeededAfterSafeLanding() {
        guard state == .connected, requiresArming, armingState == .armed else {
            return
        }

        requestArming(false)
    }

    // MARK: - Private Methods

    private func startTimer() {
        stopTimer()

        self.timer = Timer.scheduledTimer(timeInterval: 0.05, target: self, selector: #selector(self.updateData), userInfo:nil, repeats:true)
    }

    private func stopTimer() {
        if timer != nil {
            timer?.invalidate()
            timer = nil
        }
    }

    @objc
    private func updateData(timer: Timer) {
        guard let commander = commander else {
            return
        }

        commander.prepareData()
        guard canSendFlightCommands else {
            sendZeroThrustIfNeeded()
            return
        }

        sendFlightData(commander.roll, pitch: commander.pitch, thrust: commander.thrust, yaw: commander.yaw)
    }

    private func sendFlightData(_ roll:Float, pitch:Float, thrust:Float, yaw:Float) {
        let commanderPacket = CommanderPacket(header: CrazyFlieHeader.commander.rawValue, roll: roll, pitch: pitch, yaw: yaw, thrust: UInt16(thrust))
        logCommanderPacket(roll: roll, pitch: pitch, thrust: thrust, yaw: yaw, simulated: isDemoMode)

        if isDemoMode {
            return
        }

        bluetoothLink.sendPacket(commanderPacket.data, callback: nil)
        print("pitch: \(pitch) roll: \(roll) thrust: \(thrust) yaw: \(yaw)")
    }

    private var canSendFlightCommands: Bool {
        return !isDetectingDeviceType && (!requiresArming || armingState == .armed)
    }

    private func sendZeroThrustIfNeeded() {
        guard requiresArming, !hasSentZeroThrustPacket else {
            return
        }

        hasSentZeroThrustPacket = true
        sendFlightData(0, pitch: 0, thrust: 0, yaw: 0)
    }

    private func prepareFlightStateForConnectedDevice() {
        let needsArming = shouldAssumeBrushless()
        setFlightRequirement(needsArming, deviceType: nil)

        if needsArming {
            hasSentZeroThrustPacket = false
            sendZeroThrustIfNeeded()
        }
    }

    private func shouldAssumeBrushless() -> Bool {
        if UserDefaults.standard.bool(forKey: "forceBrushlessArmControl") {
            return true
        }

        guard let name = bluetoothLink.connectedName?.lowercased() else {
            return false
        }

        return name.contains("brushless") || name.contains("cf21bl") || name.contains("c21b")
    }

    private func requestDeviceType() {
        guard !isDemoMode else {
            return
        }

        detectionTimeoutWorkItem?.cancel()
        isDetectingDeviceType = true
        delegate?.didUpdateFlightStatus()

        let workItem = DispatchWorkItem { [weak self] in
            self?.isDetectingDeviceType = false
            self?.detectionTimeoutWorkItem = nil
            self?.delegate?.didUpdateFlightStatus()
        }

        detectionTimeoutWorkItem = workItem
        appendDebugLog("TX device type request")
        bluetoothLink.sendPacket(packet(header: CRTP.platformVersionHeader,
                                        payload: [CRTP.getDeviceTypeNameCommand]),
                                 callback: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func requestArming(_ arm: Bool) {
        pendingArmingTarget = arm
        armingTimeoutWorkItem?.cancel()

        armingState = arm ? .arming : .disarming
        delegate?.didUpdateFlightStatus()

        let payload: [UInt8] = [CRTP.armSystemCommand, arm ? 1 : 0]
        appendDebugLog("\(isDemoMode ? "DEMO" : "TX") Supervisor port 9 ch 1 -> CMD_ARM_SYSTEM payload [\(payload[0]), \(payload[1])]")

        if isDemoMode {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self, self.pendingArmingTarget == arm else {
                    return
                }

                self.finishArmingRequest(isArmed: arm, updateZeroPacketState: true)
            }

            armingTimeoutWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
            hasSentZeroThrustPacket = false
            sendZeroThrustIfNeeded()
            return
        }

        bluetoothLink.sendPacket(packet(header: CRTP.legacySupervisorHeader, payload: payload), callback: nil)
        bluetoothLink.sendPacket(packet(header: CRTP.platformCommandHeader, payload: payload)) { [weak self] success in
            guard let self = self, self.pendingArmingTarget == arm else {
                return
            }

            if !success {
                self.finishArmingRequest(isArmed: !arm, updateZeroPacketState: true)
            }
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.pendingArmingTarget == arm else {
                return
            }

            self.finishArmingRequest(isArmed: arm, updateZeroPacketState: true)
        }

        hasSentZeroThrustPacket = false
        sendZeroThrustIfNeeded()

        armingTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    private func finishArmingRequest(isArmed: Bool, updateZeroPacketState: Bool) {
        armingTimeoutWorkItem?.cancel()
        armingTimeoutWorkItem = nil
        pendingArmingTarget = nil
        armingState = isArmed ? .armed : .disarmed
        appendDebugLog(isArmed ? "Arm state: armed" : "Arm state: disarmed")

        if updateZeroPacketState && !isArmed {
            hasSentZeroThrustPacket = false
            sendZeroThrustIfNeeded()
        }

        delegate?.didUpdateFlightStatus()
    }

    private func handleIncomingPacket(_ packet: Data) {
        guard let header = packet.first else {
            return
        }

        let payload = [UInt8](packet.dropFirst())

        if header == CRTP.platformVersionHeader,
           payload.first == CRTP.getDeviceTypeNameCommand {
            handleDeviceTypeResponse(payload)
            return
        }

        if header == CRTP.platformCommandHeader || header == CRTP.legacySupervisorHeader,
           payload.first == CRTP.armSystemCommand {
            handleArmResponse(payload)
        }
    }

    private func handleDeviceTypeResponse(_ payload: [UInt8]) {
        detectionTimeoutWorkItem?.cancel()
        detectionTimeoutWorkItem = nil
        isDetectingDeviceType = false

        let rawDeviceType = String(data: Data(payload.dropFirst()), encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet.controlCharacters))
        appendDebugLog("RX device type -> \(rawDeviceType ?? "unknown")")

        let isBrushless = UserDefaults.standard.bool(forKey: "forceBrushlessArmControl")
            || rawDeviceType == CRTP.brushlessDeviceType
            || rawDeviceType?.localizedCaseInsensitiveContains("brushless") == true

        setFlightRequirement(isBrushless, deviceType: rawDeviceType)
    }

    private func handleArmResponse(_ payload: [UInt8]) {
        if payload.count >= 3 {
            let didSucceed = payload[1] != 0
            let isArmed = payload[2] != 0
            finishArmingRequest(isArmed: isArmed, updateZeroPacketState: !didSucceed)
            return
        }

        if let pendingArmingTarget = pendingArmingTarget {
            finishArmingRequest(isArmed: pendingArmingTarget, updateZeroPacketState: true)
        }
    }

    private func setFlightRequirement(_ needsArming: Bool, deviceType: String?) {
        detectedDeviceType = deviceType
        requiresArming = needsArming
        armingState = needsArming ? .disarmed : .unavailable
        if let deviceType = deviceType {
            appendDebugLog("Flight mode: \(needsArming ? "brushless" : "legacy") for \(deviceType)")
        }
        delegate?.didUpdateFlightStatus()
    }

    private func resetFlightState() {
        detectionTimeoutWorkItem?.cancel()
        detectionTimeoutWorkItem = nil
        armingTimeoutWorkItem?.cancel()
        armingTimeoutWorkItem = nil
        detectedDeviceType = nil
        requiresArming = false
        armingState = .unavailable
        isDetectingDeviceType = false
        isDemoMode = false
        pendingArmingTarget = nil
        hasSentZeroThrustPacket = false
        lastCommanderLogSignature = nil
    }

    private func packet(header: UInt8, payload: [UInt8]) -> Data {
        return Data([header] + payload)
    }

    private func logCommanderPacket(roll: Float, pitch: Float, thrust: Float, yaw: Float, simulated: Bool) {
        let signature = String(format: "r%.1f_p%.1f_y%.1f_t%.0f", roll, pitch, yaw, thrust)
        guard signature != lastCommanderLogSignature else {
            return
        }

        lastCommanderLogSignature = signature
        appendDebugLog(String(format: "%@ Legacy 0x30 -> roll %.1f pitch %.1f yaw %.1f thrust %.0f",
                              simulated ? "DEMO" : "TX",
                              roll,
                              pitch,
                              yaw,
                              thrust))
    }

    private func appendDebugLog(_ message: String) {
        let line = "[\(timestamp())] \(message)"
        debugLogLines.append(line)

        if debugLogLines.count > 14 {
            debugLogLines.removeFirst(debugLogLines.count - 14)
        }

        debugLogText = debugLogLines.joined(separator: "\n")
        print(line)
        delegate?.didUpdateFlightStatus()
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}
