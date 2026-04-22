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
    weak var delegate: ViewModelDelegate?
    let leftJoystickProvider: BCJoystickViewModel
    let rightJoystickProvider: BCJoystickViewModel
    
    private var motionLink: MotionLink?
    private var crazyFlie: CrazyFlie?
    private var safeLandingCommander: SafeLandingCrazyFlieCommander?
    private var sensitivity: Sensitivity = .slow
    private var controlMode: ControlMode = ControlMode.current ?? .mode1
    
    fileprivate(set) var progress: Float = 0
    fileprivate(set) var topButtonTitle: String
    
    init() {
        topButtonTitle = "Connect"
        
        leftJoystickProvider = BCJoystickViewModel()
        rightJoystickProvider = BCJoystickViewModel(deadbandX: 0.1, vLabelLeft: true)
        
        leftJoystickProvider.add(observer: self)
        rightJoystickProvider.add(observer: self)
        
        crazyFlie = CrazyFlie(delegate: self)
        loadDefaults()
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

    var showsArmButton: Bool {
        guard let crazyFlie = crazyFlie else {
            return false
        }

        return crazyFlie.state == .connected && crazyFlie.requiresArming
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
        guard let crazyFlie = crazyFlie, showsArmButton else {
            return false
        }

        switch crazyFlie.armingState {
        case .arming, .disarming:
            return false
        default:
            return true
        }
    }

    var statusText: String {
        guard let crazyFlie = crazyFlie else {
            return "Place both thumbs to enable control"
        }

        if isSafeLandingActive {
            return "Place both thumbs to enable control"
        }

        if crazyFlie.state == .connected && crazyFlie.isDetectingDeviceType {
            return "Detecting Crazyflie type..."
        }

        if showsArmButton {
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
        if isSafeLandingActive {
            return false
        }

        if crazyFlie?.isDetectingDeviceType == true {
            return false
        }

        if showsArmButton {
            return bothThumbsOnJoystick && crazyFlie?.armingState == .armed
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
        crazyFlie?.connect(nil)
    }

    func toggleArm() {
        crazyFlie?.toggleArm()
    }

    func toggleDemoMode() {
        crazyFlie?.toggleDemoSession()
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
        delegate?.signalUpdate()
    }

    func didUpdateFlightStatus() {
        delegate?.signalUpdate()
    }
    
    func didFail(with title: String, message: String?) {
        delegate?.signalFailed(with: title, message: message)
    }
}
