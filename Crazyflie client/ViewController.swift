//
//  ViewController.swift
//  Crazyflie client
//
//  Created by Martin Eberl on 23.01.17.
//  Copyright © 2017 Bitcraze. All rights reserved.
//

import UIKit

final class ViewController: UIViewController {
    private var leftJoystick: BCJoystick?
    private var rightJoystick: BCJoystick?
    
    private var viewModel: ViewModel?
    private var settingsViewController: SettingsViewController?
    
    @IBOutlet weak var unlockLabel: UILabel!
    @IBOutlet weak var safeLandingLabel: UILabel!
    @IBOutlet weak var armButton: UIButton!
    @IBOutlet weak var nearbyCrazyflieButton: UIButton!
    @IBOutlet weak var demoButton: UIButton!
    @IBOutlet weak var debugTextView: UITextView!
    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var settingsButton: UIButton!
    @IBOutlet weak var connectProgress: UIProgressView!
    @IBOutlet weak var leftView: UIView!
    @IBOutlet weak var rightView: UIView!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        if viewModel == nil {
            viewModel = ViewModel()
            viewModel?.delegate = self
        }
        
        setupUI()
        viewModel?.updateSettings()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        viewModel?.loadSettings()
        applyTheme()
        updateUI()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyTheme()
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    //MARK: - IBActions
    
    @IBAction func connectClicked(_ sender: Any) {
        viewModel?.connect()
    }

    @IBAction func nearbyCrazyflieClicked(_ sender: UIButton) {
        if #available(iOS 14.0, *) {
            return
        }

        presentNearbyCrazyflies(from: sender)
    }

    @IBAction func armClicked(_ sender: Any) {
        viewModel?.toggleArm()
    }

    @IBAction func demoClicked(_ sender: Any) {
        viewModel?.toggleDemoMode()
    }
    
    @IBAction func settingsClicked(_ sender: Any) {
        performSegue(withIdentifier: "settings", sender: nil)
    }
    
    //MARK: - Private
    
    private func setupUI() {
        guard let viewModel = viewModel else { return }
        connectProgress.progress = 0
        
        debugTextView.layer.borderWidth = 1
        debugTextView.layer.cornerRadius = 4
        debugTextView.isEditable = false
        debugTextView.textContainerInset = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        nearbyCrazyflieButton.titleLabel?.adjustsFontSizeToFitWidth = true
        nearbyCrazyflieButton.titleLabel?.minimumScaleFactor = 0.75
        nearbyCrazyflieButton.titleLabel?.lineBreakMode = .byTruncatingTail
        applyTheme()
        
        //Init joysticks
        let frame = UIScreen.main.bounds
        
        let leftViewModel = viewModel.leftJoystickProvider
        let leftJoystick = BCJoystick(frame: frame, viewModel: leftViewModel)
        leftViewModel.delegate = leftJoystick
        leftViewModel.add(observer: viewModel)
        leftView.addSubview(leftJoystick)
        self.leftJoystick = leftJoystick
        
        let rightViewModel = viewModel.rightJoystickProvider
        let rightJoystick = BCJoystick(frame: frame, viewModel: rightViewModel)
        rightViewModel.delegate = rightJoystick
        rightViewModel.add(observer: viewModel)
        rightView.addSubview(rightJoystick)
        self.rightJoystick = rightJoystick
    }

    private func applyTheme() {
        let accentColor = AppTheme.accentColor

         view.backgroundColor = AppTheme.backgroundColor
        [leftView, rightView].forEach {
            $0?.backgroundColor = .clear
            $0?.layer.cornerRadius = 18
            $0?.layer.borderWidth = 0
            $0?.layer.borderColor = UIColor.clear.cgColor
            $0?.clipsToBounds = true
        }

        unlockLabel.textColor = AppTheme.primaryTextColor
        safeLandingLabel.textColor = UIColor(red: 0.83, green: 0.14, blue: 0.12, alpha: 1.0)
        debugTextView.backgroundColor = AppTheme.secondaryBackgroundColor
        debugTextView.textColor = AppTheme.primaryTextColor
        debugTextView.keyboardAppearance = AppTheme.isDarkModeEnabled ? .dark : .default
        debugTextView.layer.borderColor = AppTheme.separatorColor.cgColor

        connectProgress.progressTintColor = accentColor
        connectProgress.trackTintColor = AppTheme.progressTrackColor

        [nearbyCrazyflieButton, connectButton, armButton, demoButton, settingsButton].forEach {
            $0?.layer.borderColor = accentColor.cgColor
            $0?.setTitleColor(accentColor, for: .normal)
            $0?.setTitleColor(accentColor.withAlphaComponent(0.45), for: .disabled)
        }
    }
    
    fileprivate func updateUI() {
        guard let viewModel = viewModel else {
            return
        }
        unlockLabel.isHidden = viewModel.shouldHideStatusText
        unlockLabel.text = viewModel.statusText
        safeLandingLabel.isHidden = !viewModel.isSafeLandingActive
        safeLandingLabel.text = viewModel.safeLandingWarningText
        nearbyCrazyflieButton.setTitle(viewModel.nearbyCrazyflieButtonTitle, for: .normal)
        nearbyCrazyflieButton.isEnabled = true
        armButton.isHidden = !viewModel.showsArmButton
        armButton.isEnabled = viewModel.isArmButtonEnabled
        armButton.setTitle(viewModel.armButtonTitle, for: .normal)
        demoButton.isHidden = !viewModel.showsDemoButton
        demoButton.isEnabled = viewModel.isDemoButtonEnabled
        demoButton.setTitle(viewModel.demoButtonTitle, for: .normal)
        debugTextView.isHidden = !viewModel.showsDebugLog
        debugTextView.text = viewModel.debugLogText

        if !debugTextView.isHidden && !debugTextView.text.isEmpty {
            let range = NSRange(location: debugTextView.text.count - 1, length: 1)
            debugTextView.scrollRangeToVisible(range)
        }
        
        leftJoystick?.hLabel.text = viewModel.leftXTitle
        leftJoystick?.vLabel.text = viewModel.leftYTitle
        rightJoystick?.hLabel.text = viewModel.rightXTitle
        rightJoystick?.vLabel.text = viewModel.rightYTitle
        
        connectProgress.setProgress(viewModel.progress, animated: true)
        connectButton.setTitle(viewModel.topButtonTitle, for: .normal)
        connectButton.isEnabled = viewModel.isConnectButtonEnabled
        updateNearbyCrazyflieMenu()
    }
    
    // MARK: - Navigation
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "settings" {
            guard let viewController = segue.destination as? SettingsViewController else {
                return
            }
            
            viewController.viewModel = viewModel?.settingsViewModel
            viewController.flightViewModel = viewModel
        }
    }

}

extension ViewController: ViewModelDelegate {
    func signalUpdate() {
        updateUI()
    }
    
    func signalFailed(with title: String, message: String?) {
        let alert = UIAlertController(title: title,
                                      message: message,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Ok",
                                      style: .default,
                                      handler: {[weak alert] (action) in
            alert?.dismiss(animated: true, completion: nil)
        }))
        present(alert, animated: true, completion: nil)
    }
}

private extension ViewController {
    func updateNearbyCrazyflieMenu() {
        guard #available(iOS 14.0, *),
              let viewModel = viewModel else {
            return
        }

        nearbyCrazyflieButton.menu = makeNearbyCrazyflieMenu(viewModel: viewModel)
        nearbyCrazyflieButton.showsMenuAsPrimaryAction = true
    }

    @available(iOS 14.0, *)
    func makeNearbyCrazyflieMenu(viewModel: ViewModel) -> UIMenu {
        var actions = viewModel.nearbyCrazyflieOptions.map { option in
            UIAction(title: option.title,
                     image: nil,
                     identifier: nil,
                     discoverabilityTitle: nil,
                     attributes: [],
                     state: option.isSelected ? .on : .off) { [weak self] _ in
                self?.viewModel?.selectNearbyCrazyflie(with: option.identifier)
            }
        }

        actions.insert(UIAction(title: "Scan Again",
                                image: nil,
                                identifier: nil,
                                discoverabilityTitle: nil,
                                attributes: [],
                                state: .off) { [weak self] _ in
            self?.viewModel?.refreshNearbyCrazyflies()
        }, at: 0)

        if actions.count == 1 {
            actions.append(UIAction(title: "No Crazyflies found",
                                    image: nil,
                                    identifier: nil,
                                    discoverabilityTitle: nil,
                                    attributes: [.disabled],
                                    state: .off) { _ in })
        }

        return UIMenu(title: "Nearby Crazyflies", children: actions)
    }

    func presentNearbyCrazyflies(from sourceView: UIView) {
        guard let viewModel = viewModel else {
            return
        }

        let alert = UIAlertController(title: "Nearby Crazyflies",
                                      message: viewModel.nearbyCrazyflieButtonHint,
                                      preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "Scan Again", style: .default) { [weak self] _ in
            self?.viewModel?.refreshNearbyCrazyflies()
        })

        for option in viewModel.nearbyCrazyflieOptions {
            let title = option.isSelected ? "[Selected] \(option.title)" : option.title
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.viewModel?.selectNearbyCrazyflie(with: option.identifier)
            })
        }

        if viewModel.nearbyCrazyflieOptions.isEmpty {
            alert.addAction(UIAlertAction(title: "No Crazyflies found", style: .default, handler: nil))
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
        }

        present(alert, animated: true, completion: nil)
    }
}
