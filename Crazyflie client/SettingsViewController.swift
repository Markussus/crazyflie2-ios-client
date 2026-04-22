//
//  SettingsViewController.swift
//  Crazyflie client
//
//  Created by Martin Eberl on 24.01.17.
//  Copyright © 2017 Bitcraze. All rights reserved.
//

import UIKit

final class SettingsViewController: UIViewController {
    var viewModel: SettingsViewModel?
    
    @IBOutlet weak var pitchrollSensitivity: UITextField!
    @IBOutlet weak var thrustSensitivity: UITextField!
    @IBOutlet weak var yawSensitivity: UITextField!
    @IBOutlet weak var sensitivitySelector: UISegmentedControl!
    @IBOutlet weak var controlModeSelector: UISegmentedControl!
    
    @IBOutlet weak var leftXLabel: UILabel!
    @IBOutlet weak var leftYLabel: UILabel!
    @IBOutlet weak var rightXLabel: UILabel!
    @IBOutlet weak var rightYLabel: UILabel!
    @IBOutlet weak var safeLandingLabel: UILabel!
    @IBOutlet weak var safeLandingSwitch: UISwitch!
    @IBOutlet weak var landingDurationLabel: UILabel!
    @IBOutlet weak var landingDurationSlider: UISlider!
    @IBOutlet weak var landingDurationTextField: UITextField!
    @IBOutlet weak var darkModeLabel: UILabel!
    @IBOutlet weak var darkModeSwitch: UISwitch!
    @IBOutlet weak var closeButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        viewModel?.delegate = self
        applyTheme()
        updateUI()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyTheme()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        viewModel?.delegate = nil
    }
    
    // MARK: - Private Methods
    
    private func setupUI() {
        applyTheme()
        
        if MotionLink().canAccessMotion {
            controlModeSelector.insertSegment(withTitle: "Tilt Mode", at: 4, animated: true)
        }
    }

    private func applyTheme() {
        view.backgroundColor = AppTheme.backgroundColor
        closeButton.layer.borderColor = AppTheme.accentColor.cgColor
        safeLandingSwitch.onTintColor = AppTheme.accentColor
        darkModeSwitch.onTintColor = AppTheme.accentColor

        [pitchrollSensitivity, thrustSensitivity, yawSensitivity, landingDurationTextField].forEach {
            $0?.backgroundColor = AppTheme.secondaryBackgroundColor
            $0?.textColor = AppTheme.primaryTextColor
            $0?.keyboardAppearance = AppTheme.isDarkModeEnabled ? .dark : .default
        }

        [leftXLabel, leftYLabel, rightXLabel, rightYLabel, safeLandingLabel, landingDurationLabel, darkModeLabel].forEach {
            $0?.textColor = AppTheme.primaryTextColor
        }

        landingDurationSlider.tintColor = AppTheme.accentColor
    }
    
    fileprivate func updateUI() {
        guard let viewModel = viewModel else {
            return
        }
        
        sensitivitySelector.selectedSegmentIndex = viewModel.sensitivity.index
        controlModeSelector.selectedSegmentIndex = viewModel.controlMode.index
        
        leftXLabel.text = viewModel.leftXTitle
        leftYLabel.text = viewModel.leftYTitle
        rightXLabel.text = viewModel.rightXTitle
        rightYLabel.text = viewModel.rightYTitle
        safeLandingSwitch.isOn = viewModel.isSafeLandingEnabled
        let landingDuration = viewModel.landingDuration
        landingDurationSlider.minimumValue = SafeLandingSettings.minDuration
        landingDurationSlider.maximumValue = SafeLandingSettings.maxDuration
        landingDurationSlider.value = landingDuration
        landingDurationTextField.text = formattedLandingDuration(landingDuration)
        darkModeSwitch.isOn = AppTheme.isDarkModeEnabled
        
        if let pitch = viewModel.pitch {
            pitchrollSensitivity.text = String(describing: pitch)
            pitchrollSensitivity.isEnabled = viewModel.canEditValues
        }
        if let thrust = viewModel.thrust {
            thrustSensitivity.text = String(describing: thrust)
            thrustSensitivity.isEnabled = viewModel.canEditValues
        }
        if let yaw = viewModel.yaw {
            yawSensitivity.text = String(describing: yaw)
            yawSensitivity.isEnabled = viewModel.canEditValues
        }
    }
    
    @IBAction func sensitivityModeChanged(_ sender: Any) {
        viewModel?.didSetSensitivityMode(at: sensitivitySelector.selectedSegmentIndex)
    }
    
    @IBAction func controlModeChanged(_ sender: Any) {
        viewModel?.didSetControlMode(at: controlModeSelector.selectedSegmentIndex)
    }

    @IBAction func safeLandingChanged(_ sender: Any) {
        viewModel?.didSetSafeLandingEnabled(safeLandingSwitch.isOn)
    }

    @IBAction func landingDurationSliderChanged(_ sender: Any) {
        let roundedValue = round(landingDurationSlider.value * 10) / 10
        let clampedValue = viewModel?.didUpdate(landingDuration: roundedValue) ?? roundedValue
        syncLandingDurationControls(with: clampedValue)
    }

    @IBAction func darkModeChanged(_ sender: Any) {
        AppTheme.isDarkModeEnabled = darkModeSwitch.isOn
        applyTheme()
    }
    
    @IBAction func closeClicked(_ sender: Any) {
        if viewModel?.canEditValues == true {
            [pitchrollSensitivity, thrustSensitivity, yawSensitivity].forEach { $0.resignFirstResponder() }
        }
        landingDurationTextField.resignFirstResponder()
        dismiss(animated: true, completion: nil)
    }
    
    @objc func endEditing(_ force: Bool) -> Bool {
        if viewModel?.canEditValues == true {
            // Called only for sensitivity text fields
            viewModel?.sensitivity.settings?.pitchRate = pitchrollSensitivity.text.flatMap(Float.init) ?? 0.0
            viewModel?.sensitivity.settings?.maxThrust = thrustSensitivity.text.flatMap(Float.init) ?? 0.0
            viewModel?.sensitivity.settings?.yawRate = yawSensitivity.text.flatMap(Float.init) ?? 0.0
        }

        let durationInput = landingDurationTextField.text.flatMap(Float.init) ?? SafeLandingSettings.duration
        let clampedDuration = viewModel?.didUpdate(landingDuration: durationInput) ?? SafeLandingSettings.clamp(durationInput)
        syncLandingDurationControls(with: clampedDuration)
        return true
    }

    private func syncLandingDurationControls(with duration: Float) {
        landingDurationSlider.value = duration
        landingDurationTextField.text = formattedLandingDuration(duration)
    }

    private func formattedLandingDuration(_ duration: Float) -> String {
        if duration.rounded(.towardZero) == duration {
            return String(Int(duration))
        }

        return String(format: "%.1f", duration)
    }
}

extension SettingsViewController: SettingsViewModelDelegate {
    func didUpdate() {
        updateUI()
    }
}
