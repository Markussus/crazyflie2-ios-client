//
//  ViewModel.swift
//  Crazyflie client
//
//  Created by Martin Eberl on 23.01.17.
//  Copyright © 2017 Bitcraze. All rights reserved.
//

import Foundation

protocol ViewModelDelegate: AnyObject {
    func signalUpdate()
    func signalFailed(with title: String, message: String?)
}

final class ViewModel {
    struct NearbyCrazyflieOption {
        let identifier: UUID
        let title: String
        let isReadyToPair: Bool
        let isSelected: Bool
    }

    weak var delegate: ViewModelDelegate?
    let leftJoystickProvider: BCJoystickViewModel
    let rightJoystickProvider: BCJoystickViewModel
    
    private var motionLink: MotionLink?
    private var crazyFlie: CrazyFlie?
    private var safeLandingCommander: SafeLandingCrazyFlieCommander?
    private var nearbyCrazyflies: [BluetoothLink.DiscoveredCrazyflie] = []
    private var selectedCrazyflieID: UUID?
    private var sensitivity: Sensitivity = .slow
    private var controlMode: ControlMode = ControlMode.current ?? .mode1
    private(set) var isScanningForNearbyCrazyflies = false
    
    fileprivate(set) var progress: Float = 0
    fileprivate(set) var topButtonTitle: String
    
    init() {
        topButtonTitle = "Connect"
        
        leftJoystickProvider = BCJoystickViewModel()
        rightJoystickProvider = BCJoystickViewModel(deadbandX: 0.1, vLabelLeft: true)
        
        leftJoystickProvider.add(observer: self)
        rightJoystickProvider.add(observer: self)
        
        crazyFlie = CrazyFlie(delegate: self)
        crazyFlie?.bluetoothLink.onDiscoveredDevices { [weak self] devices, isScanning in
            self?.handleNearbyCrazyfliesUpdate(devices: devices, isScanning: isScanning)
        }
        loadDefaults()
        refreshNearbyCrazyflies()
    }
    
    deinit {
        leftJoystickProvider.remove(observer: self)
        rightJoystickProvider.remove(observer: self)
    }
    
    var leftXTitle: String? {
        return title(at: 0)
    }
    var rightXTitle: String? {
        return title(at: 2)
    }
    var leftYTitle: String? {
        return title(at: 1)
    }
    var rightYTitle: String? {
        return title(at: 3)
    }
    
    var bothThumbsOnJoystick: Bool {
        return leftJoystickProvider.activated && rightJoystickProvider.activated
    }

    var selectedCrazyflie: BluetoothLink.DiscoveredCrazyflie? {
        guard let selectedCrazyflieID = selectedCrazyflieID else {
            return nil
        }

        return nearbyCrazyflies.first(where: { $0.identifier == selectedCrazyflieID })
    }

    var nearbyCrazyflieOptions: [NearbyCrazyflieOption] {
        return nearbyCrazyflies.map { crazyflie in
            let isSelected = selectedCrazyflieID.map { $0 == crazyflie.identifier } ?? false
            return NearbyCrazyflieOption(identifier: crazyflie.identifier,
                                         title: nearbyCrazyflieTitle(for: crazyflie),
                                         isReadyToPair: crazyflie.isReadyToPair,
                                         isSelected: isSelected)
        }
    }

    var nearbyCrazyflieButtonTitle: String {
        if let selectedCrazyflie = selectedCrazyflie {
            return nearbyCrazyflieTitle(for: selectedCrazyflie)
        }

        if isScanningForNearbyCrazyflies {
            return "Scanning nearby Crazyflies..."
        }

        if nearbyCrazyflies.isEmpty {
            return "Select Crazyflie"
        }

        return "Choose nearby Crazyflie"
    }

    var nearbyCrazyflieButtonHint: String {
        if isScanningForNearbyCrazyflies {
            return "Scanning..."
        }

        if nearbyCrazyflies.isEmpty {
            return "No Crazyflies found yet"
        }

        return "Tap to choose"
    }

    var showsArmButton: Bool {
        return true
    }

    var demoButtonTitle: String {
        guard let crazyFlie = crazyFlie else {
            return "Demo"
        }

        return crazyFlie.isDemoMode ? "End Demo" : "Demo"
    }

    var isDemoButtonEnabled: Bool {
        guard let crazyFlie = crazyFlie else {
            return false
        }

        return crazyFlie.isDemoMode || crazyFlie.state == .idle
    }

    var debugLogText: String {
        return crazyFlie?.debugLogText ?? "Debug log ready."
    }

    var showsDemoButton: Bool {
        return AdvancedOptionsSettings.showDemoButton
    }

    var showsDebugLog: Bool {
        return AdvancedOptionsSettings.showDebugLog
    }

    var isSafeLandingActive: Bool {
        return safeLandingCommander?.isSafeLandingActive == true
    }

    var safeLandingWarningText: String {
        return "Safe landing in progress"
    }

    var armButtonTitle: String {
        guard let armingState = crazyFlie?.armingState else {
            return "Arm"
        }

        switch armingState {
        case .arming:
            return "Arming..."
        case .armed:
            return "Disarm"
        case .disarming:
            return "Disarming..."
        case .disarmed, .unavailable:
            return "Arm"
        }
    }

    var isArmButtonEnabled: Bool {
        return true
    }

    var isConnectButtonEnabled: Bool {
        return true
    }

    var statusText: String {
        guard let crazyFlie = crazyFlie else {
            return "Select a nearby Crazyflie to connect"
        }

        if isSafeLandingActive {
            return "Place both thumbs to enable control"
        }

        if crazyFlie.state != .connected {
            if isScanningForNearbyCrazyflies {
                return "Scanning for nearby Crazyflies..."
            }

            if let selectedCrazyflie = selectedCrazyflie {
                return selectedCrazyflie.isReadyToPair
                    ? "\(selectedCrazyflie.name) is ready to pair"
                    : "\(selectedCrazyflie.name) is nearby but not ready to pair"
            }

            return nearbyCrazyflies.isEmpty
                ? "No nearby Crazyflies found. Open the list to scan again"
                : "Select a nearby Crazyflie to connect"
        }

        if crazyFlie.state == .connected && crazyFlie.isDetectingDeviceType {
            return "Detecting Crazyflie type..."
        }

        if crazyFlie.requiresArming {
            switch crazyFlie.armingState {
            case .arming:
                return "Arming brushless system..."
            case .armed:
                return bothThumbsOnJoystick ? "Brushless armed" : "Brushless armed. Place both thumbs to enable control"
            case .disarming:
                return "Disarming brushless system..."
            case .disarmed:
                return "Brushless connected. Tap Arm to enable control"
            case .unavailable:
                return "Detecting Crazyflie type..."
            }
        }

        return "Place both thumbs to enable control"
    }

    var shouldHideStatusText: Bool {
        guard let crazyFlie = crazyFlie else {
            return false
        }

        if crazyFlie.state != .connected {
            return false
        }

        if isSafeLandingActive {
            return false
        }

        if crazyFlie.isDetectingDeviceType {
            return false
        }

        if crazyFlie.requiresArming {
            return bothThumbsOnJoystick && crazyFlie.armingState == .armed
        }

        return bothThumbsOnJoystick
    }
    
    lazy var settingsViewModel: SettingsViewModel? = {
        guard let bluetoothLink = self.crazyFlie?.bluetoothLink else {
            return nil
        }
        let settings = SettingsViewModel(sensitivity: self.sensitivity, controlMode: self.controlMode, bluetoothLink: bluetoothLink)
        settings.add(observer: self)
        return settings
    }()
    
    // MARK: - Public Methods
    
    func loadSettings() {
        
    }
    
    func connect() {
        guard let crazyFlie = crazyFlie else {
            return
        }

        let preferredCrazyflie = selectedCrazyflie?.isReadyToPair == true ? selectedCrazyflie : nil
        crazyFlie.connect(to: preferredCrazyflie, callback: nil)
    }

    func toggleArm() {
        guard let crazyFlie = crazyFlie else {
            return
        }

        guard crazyFlie.state == .connected else {
            delegate?.signalFailed(with: "Not connected",
                                   message: "Connect a Crazyflie before using Arm.")
            return
        }

        guard crazyFlie.requiresArming else {
            delegate?.signalFailed(with: "Arm not required",
                                   message: "The connected Crazyflie does not require arming.")
            return
        }

        crazyFlie.toggleArm()
    }

    func toggleDemoMode() {
        crazyFlie?.toggleDemoSession()
    }

    func setDemoButtonVisible(_ isVisible: Bool) {
        AdvancedOptionsSettings.showDemoButton = isVisible

        if isVisible == false, crazyFlie?.isDemoMode == true {
            crazyFlie?.toggleDemoSession()
        }

        delegate?.signalUpdate()
    }

    func setDebugLogVisible(_ isVisible: Bool) {
        AdvancedOptionsSettings.showDebugLog = isVisible
        delegate?.signalUpdate()
    }

    func refreshNearbyCrazyflies() {
        crazyFlie?.refreshNearbyDevices()
    }

    func selectNearbyCrazyflie(with identifier: UUID) {
        selectedCrazyflieID = identifier
        delegate?.signalUpdate()
    }
    
    // MARK: - Private Methods
    
    private func title(at index: Int) -> String? {
        guard controlMode.titles.indices.contains(index) else { return nil }
        
        return controlMode.titles[index]
    }
    
    private func startMotionUpdate() {
        if motionLink == nil {
            motionLink = MotionLink()
        }
        motionLink?.startDeviceMotionUpdates()
        motionLink?.startAccelerometerUpdates()
    }
    
    private func stopMotionUpdate() {
        motionLink?.stopDeviceMotionUpdates()
        motionLink?.stopAccelerometerUpdates()
    }
    
    private func loadDefaults() {
        guard let url = Bundle.main.url(forResource: "DefaultPreferences", withExtension: "plist"),
            let defaultPrefs = NSDictionary(contentsOf: url) else {
                return
        }
        let defaults = UserDefaults.standard
        defaults.register(defaults: defaultPrefs as! [String : Any])
        defaults.synchronize()
        
        updateSettings()
    }
    
    func updateSettings() {
        if controlMode == .tilt,
            MotionLink().canAccessMotion {
            startMotionUpdate()
        }
        else {
            stopMotionUpdate()
        }
        
        applyCommander()
    }
    
    fileprivate func calibrateMotionIfNeeded() {
        if leftJoystickProvider.touchesChanged || rightJoystickProvider.touchesChanged, controlMode == .tilt {
            motionLink?.calibrate()
        }
    }
    
    fileprivate func changed(controlMode: ControlMode) {
        self.controlMode = controlMode
        updateSettings()
    }
    
    private func applyCommander() {
        guard let commander = controlMode.commander(
            leftJoystick: leftJoystickProvider,
            rightJoystick: rightJoystickProvider,
            motionLink: motionLink,
            settings: sensitivity.settings) else {
            crazyFlie?.commander = nil
            safeLandingCommander = nil
            return
        }

        let landingCommander = SafeLandingCrazyFlieCommander(wrapping: commander)
        landingCommander.onStateChanged = { [weak self] in
            self?.delegate?.signalUpdate()
        }
        landingCommander.onLandingCompleted = { [weak self] in
            self?.crazyFlie?.disarmIfNeededAfterSafeLanding()
        }

        safeLandingCommander = landingCommander
        crazyFlie?.commander = landingCommander
    }
    
    fileprivate func updateWith(state: CrazyFlieState) {
        topButtonTitle = "Cancel"
        switch state {
        case .idle:
            progress = 0
            topButtonTitle = "Connect"
        case .scanning:
            progress = 0
        case .connecting:
            progress = 0.25
        case .services:
            progress = 0.5
        case .characteristics:
            progress = 0.75
        case .connected:
            progress = 1
            topButtonTitle = "Disconnect"
        }
    }

    private func handleNearbyCrazyfliesUpdate(devices: [BluetoothLink.DiscoveredCrazyflie], isScanning: Bool) {
        nearbyCrazyflies = devices
        isScanningForNearbyCrazyflies = isScanning

        if let selectedCrazyflieID = selectedCrazyflieID,
           nearbyCrazyflies.contains(where: { $0.identifier == selectedCrazyflieID }) {
            delegate?.signalUpdate()
            return
        }

        if nearbyCrazyflies.isEmpty == false {
            selectedCrazyflieID = nearbyCrazyflies.first(where: { $0.isReadyToPair })?.identifier
                ?? nearbyCrazyflies.first?.identifier
        } else {
            selectedCrazyflieID = nil
        }

        delegate?.signalUpdate()
    }

    private func nearbyCrazyflieTitle(for crazyflie: BluetoothLink.DiscoveredCrazyflie) -> String {
        let pairingState = crazyflie.isConnected ? "connected" : (crazyflie.isReadyToPair ? "ready" : "not ready")
        let shortIdentifier = String(crazyflie.identifier.uuidString.suffix(6))
        return "\(crazyflie.name) [\(shortIdentifier)] - \(crazyflie.rssi) dBm - \(pairingState)"
    }
}

extension ViewModel: BCJoystickViewModelObserver {
    func didUpdateState() {
        calibrateMotionIfNeeded()

        if crazyFlie?.state == .connected {
            safeLandingCommander?.updateThumbState(leftActive: leftJoystickProvider.activated,
                                                   rightActive: rightJoystickProvider.activated)
        }
        
        delegate?.signalUpdate()
    }
}

extension ViewModel: SettingsViewModelObserver {
    func didUpdate(controlMode: ControlMode) {
        changed(controlMode: controlMode)
    }
}

//MARK: - Crazyflie
extension ViewModel: CrazyFlieDelegate {
    func didSend() {
        
    }
    
    func didUpdate(state: CrazyFlieState) {
        if state != .connected {
            safeLandingCommander?.resetSession()
        }
        updateWith(state: state)
        if state == .idle {
            refreshNearbyCrazyflies()
        }
        delegate?.signalUpdate()
    }

    func didUpdateFlightStatus() {
        delegate?.signalUpdate()
    }
    
    func didFail(with title: String, message: String?) {
        delegate?.signalFailed(with: title, message: message)
    }
}
