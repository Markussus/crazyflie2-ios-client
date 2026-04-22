//
//  SettingsViewController.swift
//  Crazyflie client
//
//  Created by Martin Eberl on 24.01.17.
//  Copyright (c) 2017 Bitcraze. All rights reserved.
//

import UIKit

final class SettingsViewController: UIViewController {
    var viewModel: SettingsViewModel?
    var flightViewModel: ViewModel?

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
    @IBOutlet weak var advancedOptionsButton: UIButton!
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

    private func setupUI() {
        if MotionLink().canAccessMotion && controlModeSelector.numberOfSegments < 5 {
            controlModeSelector.insertSegment(withTitle: "Tilt Mode", at: 4, animated: false)
        }

        [safeLandingLabel, safeLandingSwitch, landingDurationLabel, landingDurationSlider, landingDurationTextField, darkModeLabel, darkModeSwitch].forEach {
            $0?.isHidden = true
        }

        [pitchrollSensitivity, thrustSensitivity, yawSensitivity].forEach {
            $0?.layer.cornerRadius = 4
            $0?.layer.borderWidth = 1
        }

        [advancedOptionsButton, closeButton].forEach {
            $0?.layer.cornerRadius = 4
            $0?.layer.borderWidth = 1
        }

        applyTheme()
    }

    private func applyTheme() {
        view.backgroundColor = AppTheme.backgroundColor
        view.tintColor = AppTheme.accentColor

        [pitchrollSensitivity, thrustSensitivity, yawSensitivity].forEach {
            $0?.backgroundColor = AppTheme.secondaryBackgroundColor
            $0?.textColor = AppTheme.primaryTextColor
            $0?.keyboardAppearance = AppTheme.isDarkModeEnabled ? .dark : .default
            $0?.layer.borderColor = AppTheme.separatorColor.cgColor
        }

        [advancedOptionsButton, closeButton].forEach {
            $0?.layer.borderColor = AppTheme.accentColor.cgColor
            $0?.setTitleColor(AppTheme.accentColor, for: .normal)
        }

        let normalAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: AppTheme.primaryTextColor
        ]
        sensitivitySelector.setTitleTextAttributes(normalAttributes, for: .normal)
        controlModeSelector.setTitleTextAttributes(normalAttributes, for: .normal)

        applyTextTheme(to: view)
    }

    private func applyTextTheme(to rootView: UIView) {
        if rootView is UIButton || rootView is UISegmentedControl {
            return
        }

        for subview in rootView.subviews {
            if let label = subview as? UILabel {
                label.textColor = AppTheme.primaryTextColor
            }

            applyTextTheme(to: subview)
        }
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
    }

    @IBAction func landingDurationSliderChanged(_ sender: Any) {
    }

    @IBAction func darkModeChanged(_ sender: Any) {
    }

    @IBAction func advancedOptionsClicked(_ sender: Any) {
        guard let settingsViewModel = viewModel else {
            return
        }

        let advancedViewController = AdvancedSettingsViewController(settingsViewModel: settingsViewModel,
                                                                   flightViewModel: flightViewModel)
        advancedViewController.modalPresentationStyle = .fullScreen
        present(advancedViewController, animated: true, completion: nil)
    }

    @IBAction func closeClicked(_ sender: Any) {
        if viewModel?.canEditValues == true {
            [pitchrollSensitivity, thrustSensitivity, yawSensitivity].forEach { $0?.resignFirstResponder() }
        }
        dismiss(animated: true, completion: nil)
    }

    @objc func endEditing(_ force: Bool) -> Bool {
        if viewModel?.canEditValues == true {
            viewModel?.sensitivity.settings?.pitchRate = pitchrollSensitivity.text.flatMap(Float.init) ?? 0.0
            viewModel?.sensitivity.settings?.maxThrust = thrustSensitivity.text.flatMap(Float.init) ?? 0.0
            viewModel?.sensitivity.settings?.yawRate = yawSensitivity.text.flatMap(Float.init) ?? 0.0
        }
        return true
    }
}

extension SettingsViewController: SettingsViewModelDelegate {
    func didUpdate() {
        updateUI()
    }
}

private final class AdvancedSettingsViewController: UIViewController, UITextFieldDelegate {
    private let settingsViewModel: SettingsViewModel
    private weak var flightViewModel: ViewModel?

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stackView = UIStackView()
    private let titleLabel = UILabel()
    private let safeLandingLabel = UILabel()
    private let safeLandingSwitch = UISwitch()
    private let darkModeLabel = UILabel()
    private let darkModeSwitch = UISwitch()
    private let landingDurationLabel = UILabel()
    private let landingDurationSlider = UISlider()
    private let landingDurationTextField = UITextField()
    private let demoButtonLabel = UILabel()
    private let demoButtonSwitch = UISwitch()
    private let debugLogLabel = UILabel()
    private let debugLogSwitch = UISwitch()
    private let closeButton = UIButton(type: .system)
    private var preferredStackWidthConstraint: NSLayoutConstraint?

    init(settingsViewModel: SettingsViewModel, flightViewModel: ViewModel?) {
        self.settingsViewModel = settingsViewModel
        self.flightViewModel = flightViewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupUI()
        applyTheme()
        updateUI()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyTheme()
    }

    private func setupUI() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(stackView)

        stackView.axis = .vertical
        stackView.spacing = 20
        stackView.alignment = .fill
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

        titleLabel.text = "Advanced Options"
        titleLabel.font = UIFont.boldSystemFont(ofSize: 26)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 1

        landingDurationLabel.text = "Landing Duration (s)"
        landingDurationLabel.font = UIFont.boldSystemFont(ofSize: 17)
        landingDurationLabel.textAlignment = .center
        landingDurationLabel.numberOfLines = 1

        landingDurationSlider.minimumValue = SafeLandingSettings.minDuration
        landingDurationSlider.maximumValue = SafeLandingSettings.maxDuration
        landingDurationSlider.addTarget(self, action: #selector(landingDurationSliderChanged), for: .valueChanged)
        landingDurationSlider.translatesAutoresizingMaskIntoConstraints = false
        landingDurationSlider.heightAnchor.constraint(equalToConstant: 44).isActive = true

        landingDurationTextField.translatesAutoresizingMaskIntoConstraints = false
        landingDurationTextField.borderStyle = .roundedRect
        landingDurationTextField.keyboardType = .decimalPad
        landingDurationTextField.textAlignment = .center
        landingDurationTextField.delegate = self
        landingDurationTextField.addTarget(self, action: #selector(landingDurationEditingDidEnd), for: .editingDidEnd)
        landingDurationTextField.widthAnchor.constraint(equalToConstant: 90).isActive = true
        landingDurationTextField.heightAnchor.constraint(equalToConstant: 40).isActive = true

        closeButton.setTitle("Close", for: .normal)
        closeButton.layer.cornerRadius = 4
        closeButton.layer.borderWidth = 1
        closeButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 22, bottom: 10, right: 22)
        closeButton.addTarget(self, action: #selector(closeClicked), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.heightAnchor.constraint(equalToConstant: 44).isActive = true

        safeLandingSwitch.addTarget(self, action: #selector(safeLandingChanged), for: .valueChanged)
        darkModeSwitch.addTarget(self, action: #selector(darkModeChanged), for: .valueChanged)
        demoButtonSwitch.addTarget(self, action: #selector(demoButtonChanged), for: .valueChanged)
        debugLogSwitch.addTarget(self, action: #selector(debugLogChanged), for: .valueChanged)

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(makeSwitchRow(label: safeLandingLabel, text: "Safe Landing", control: safeLandingSwitch))
        stackView.addArrangedSubview(makeSwitchRow(label: darkModeLabel, text: "Dark Mode", control: darkModeSwitch))
        stackView.addArrangedSubview(landingDurationLabel)
        stackView.addArrangedSubview(landingDurationSlider)
        stackView.addArrangedSubview(makeCenteredRow(views: [landingDurationTextField]))
        stackView.addArrangedSubview(makeSwitchRow(label: demoButtonLabel, text: "Show Demo Button", control: demoButtonSwitch))
        stackView.addArrangedSubview(makeSwitchRow(label: debugLogLabel, text: "Show Debug Log", control: debugLogSwitch))
        stackView.addArrangedSubview(makeCenteredRow(views: [closeButton]))

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            stackView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20),
            stackView.widthAnchor.constraint(lessThanOrEqualToConstant: 800)
        ])

        preferredStackWidthConstraint = stackView.widthAnchor.constraint(equalToConstant: 650)
        preferredStackWidthConstraint?.priority = UILayoutPriority(999)
        preferredStackWidthConstraint?.isActive = true
    }

    private func makeSwitchRow(label: UILabel, text: String, control: UISwitch) -> UIView {
        label.text = text
        label.font = UIFont.systemFont(ofSize: 17, weight: .medium)

        let row = UIStackView(arrangedSubviews: [label, control])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.distribution = .fill
        return row
    }

    private func makeCenteredRow(views: [UIView]) -> UIView {
        let row = UIStackView(arrangedSubviews: views)
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .equalCentering
        row.spacing = 12
        return row
    }

    private func applyTheme() {
        view.backgroundColor = AppTheme.backgroundColor
        scrollView.backgroundColor = AppTheme.backgroundColor
        contentView.backgroundColor = AppTheme.backgroundColor

        [titleLabel, landingDurationLabel, safeLandingLabel, darkModeLabel, demoButtonLabel, debugLogLabel].forEach {
            $0.textColor = AppTheme.primaryTextColor
        }

        [safeLandingSwitch, darkModeSwitch, demoButtonSwitch, debugLogSwitch].forEach {
            $0.onTintColor = AppTheme.accentColor
        }

        landingDurationSlider.tintColor = AppTheme.accentColor
        landingDurationTextField.backgroundColor = AppTheme.backgroundColor
        landingDurationTextField.textColor = AppTheme.primaryTextColor
        landingDurationTextField.keyboardAppearance = AppTheme.isDarkModeEnabled ? .dark : .default
        closeButton.layer.borderColor = AppTheme.accentColor.cgColor
        closeButton.setTitleColor(AppTheme.accentColor, for: .normal)
    }

    private func updateUI() {
        safeLandingSwitch.isOn = settingsViewModel.isSafeLandingEnabled
        darkModeSwitch.isOn = AppTheme.isDarkModeEnabled

        let landingDuration = settingsViewModel.landingDuration
        landingDurationSlider.value = landingDuration
        landingDurationTextField.text = formattedLandingDuration(landingDuration)

        demoButtonSwitch.isOn = flightViewModel?.showsDemoButton ?? false
        debugLogSwitch.isOn = flightViewModel?.showsDebugLog ?? false

        let canShowDebugLog = demoButtonSwitch.isOn
        debugLogSwitch.isEnabled = canShowDebugLog
        debugLogLabel.alpha = canShowDebugLog ? 1.0 : 0.45
        debugLogSwitch.alpha = canShowDebugLog ? 1.0 : 0.45
    }

    @objc private func safeLandingChanged() {
        settingsViewModel.didSetSafeLandingEnabled(safeLandingSwitch.isOn)
        updateUI()
    }

    @objc private func darkModeChanged() {
        AppTheme.isDarkModeEnabled = darkModeSwitch.isOn
        applyTheme()
    }

    @objc private func landingDurationSliderChanged() {
        let roundedValue = round(landingDurationSlider.value * 10) / 10
        let clampedValue = settingsViewModel.didUpdate(landingDuration: roundedValue)
        landingDurationSlider.value = clampedValue
        landingDurationTextField.text = formattedLandingDuration(clampedValue)
    }

    @objc private func landingDurationEditingDidEnd() {
        let durationInput = landingDurationTextField.text.flatMap(Float.init) ?? settingsViewModel.landingDuration
        let clampedValue = settingsViewModel.didUpdate(landingDuration: durationInput)
        landingDurationSlider.value = clampedValue
        landingDurationTextField.text = formattedLandingDuration(clampedValue)
    }

    @objc private func demoButtonChanged() {
        flightViewModel?.setDemoButtonVisible(demoButtonSwitch.isOn)
        if demoButtonSwitch.isOn == false {
            debugLogSwitch.isOn = false
        }
        updateUI()
    }

    @objc private func debugLogChanged() {
        flightViewModel?.setDebugLogVisible(debugLogSwitch.isOn)
        updateUI()
    }

    @objc private func closeClicked() {
        view.endEditing(true)
        dismiss(animated: true, completion: nil)
    }

    @objc private func backgroundTapped() {
        view.endEditing(true)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        landingDurationEditingDidEnd()
        textField.resignFirstResponder()
        return true
    }

    private func formattedLandingDuration(_ duration: Float) -> String {
        if duration.rounded(.towardZero) == duration {
            return String(Int(duration))
        }

        return String(format: "%.1f", duration)
    }
}
