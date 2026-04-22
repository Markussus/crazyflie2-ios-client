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
    @IBOutlet weak var armButton: UIButton!
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
            $0?.backgroundColor = AppTheme.secondaryBackgroundColor
            $0?.layer.cornerRadius = 18
            $0?.layer.borderWidth = 1
            $0?.layer.borderColor = AppTheme.separatorColor.cgColor
            $0?.clipsToBounds = true
        }

        unlockLabel.textColor = AppTheme.primaryTextColor
        debugTextView.backgroundColor = AppTheme.secondaryBackgroundColor
        debugTextView.textColor = AppTheme.primaryTextColor
        debugTextView.keyboardAppearance = AppTheme.isDarkModeEnabled ? .dark : .default
        debugTextView.layer.borderColor = AppTheme.separatorColor.cgColor

        connectProgress.progressTintColor = accentColor
        connectProgress.trackTintColor = AppTheme.progressTrackColor

        connectButton.layer.borderColor = accentColor.cgColor
        armButton.layer.borderColor = accentColor.cgColor
        demoButton.layer.borderColor = accentColor.cgColor
        settingsButton.layer.borderColor = accentColor.cgColor
    }
    
    fileprivate func updateUI() {
        guard let viewModel = viewModel else {
            return
        }
        unlockLabel.isHidden = viewModel.shouldHideStatusText
        unlockLabel.text = viewModel.statusText
        armButton.isHidden = !viewModel.showsArmButton
        armButton.isEnabled = viewModel.isArmButtonEnabled
        armButton.setTitle(viewModel.armButtonTitle, for: .normal)
        demoButton.isEnabled = viewModel.isDemoButtonEnabled
        demoButton.setTitle(viewModel.demoButtonTitle, for: .normal)
        debugTextView.text = viewModel.debugLogText

        if !debugTextView.text.isEmpty {
            let range = NSRange(location: debugTextView.text.count - 1, length: 1)
            debugTextView.scrollRangeToVisible(range)
        }
        
        leftJoystick?.hLabel.text = viewModel.leftXTitle
        leftJoystick?.vLabel.text = viewModel.leftYTitle
        rightJoystick?.hLabel.text = viewModel.rightXTitle
        rightJoystick?.vLabel.text = viewModel.rightYTitle
        
        connectProgress.setProgress(viewModel.progress, animated: true)
        connectButton.setTitle(viewModel.topButtonTitle, for: .normal)
    }
    
    // MARK: - Navigation
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "settings" {
            guard let viewController = segue.destination as? SettingsViewController else {
                return
            }
            
            viewController.viewModel = viewModel?.settingsViewModel
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
