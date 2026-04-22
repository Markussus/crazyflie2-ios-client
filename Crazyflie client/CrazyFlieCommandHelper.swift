//
//  CrazyFlieCommandHelper.swift
//  Crazyflie client
//
//  Created by Martin Eberl on 21.01.17.
//  Copyright © 2017 Bitcraze. All rights reserved.
//

import Foundation

let LINEAR_PR = true
let LINEAR_THRUST = true

protocol CrazyFlieDataProviderProtocol {
    var value: Float { get }
}

protocol CrazyFlieXProvideable {
    var x: Float { get }
}

protocol CrazyFlieYProvideable {
    var y: Float { get }
}

enum CrazyFlieDataProvider {
    case x(provider: CrazyFlieXProvideable)
    case y(provider: CrazyFlieYProvideable)
    
    var provider: CrazyFlieDataProviderProtocol {
        switch self {
        case .x(let provider):
            return SimpleXDataProvider(provider)
        case .y(let provider):
            return SimpleYDataProvider(provider)
        }
    }
}

final class SimpleXDataProvider: CrazyFlieDataProviderProtocol {
    let providable: CrazyFlieXProvideable
    
    init(_ providable: CrazyFlieXProvideable) {
        self.providable = providable
    }
    
    var value: Float {
        return providable.x
    }
}

final class SimpleYDataProvider: CrazyFlieDataProviderProtocol {
    let providable: CrazyFlieYProvideable
    
    init(_ providable: CrazyFlieYProvideable) {
        self.providable = providable
    }
    
    var value: Float {
        return providable.y
    }
}

final class SimpleCrazyFlieCommander: CrazyFlieCommander {
 
    struct BoundsValue {
        let minValue: Float
        let maxValue: Float
        var value: Float
    }
    
    private var pitchBounds = BoundsValue(minValue: 0, maxValue: 1, value: 0)
    private var rollBounds = BoundsValue(minValue: 0, maxValue: 1, value: 0)
    private var thrustBounds = BoundsValue(minValue: 0, maxValue: 1, value: 0)
    private var yawBounds = BoundsValue(minValue: 0, maxValue: 1, value: 0)

    private let pitchRate: Float
    private let yawRate: Float
    private let maxThrust: Float
    private let allowNegativeValues: Bool
    
    private let pitchProvider: CrazyFlieDataProvider
    private let yawProvider: CrazyFlieDataProvider
    private let rollProvider: CrazyFlieDataProvider
    private let thrustProvider: CrazyFlieDataProvider
    
    init(pitchProvider: CrazyFlieDataProvider,
         rollProvider: CrazyFlieDataProvider,
         yawProvider: CrazyFlieDataProvider,
         thrustProvider: CrazyFlieDataProvider,
         settings: Settings,
         allowNegativeValues: Bool = true) {
        
        self.pitchProvider = pitchProvider
        self.yawProvider = yawProvider
        self.rollProvider = rollProvider
        self.thrustProvider = thrustProvider
        self.allowNegativeValues = allowNegativeValues
        
        pitchRate = settings.pitchRate
        yawRate = settings.yawRate
        maxThrust = settings.maxThrust
    }
    
    var pitch: Float {
        return pitchBounds.value
    }
    var roll: Float {
        return rollBounds.value
    }
    var thrust: Float {
        return thrustBounds.value
    }
    var yaw: Float {
        return yawBounds.value
    }
    
    func prepareData() {
        pitchBounds.value = pitch(from: pitchProvider.provider.value)
        rollBounds.value = roll(from: rollProvider.provider.value)
        thrustBounds.value = thrust(from: thrustProvider.provider.value)
        yawBounds.value = yaw(from: yawProvider.provider.value)
    }
    
    private func pitch(from control: Float) -> Float {
        if LINEAR_PR {
            if control >= 0
                || allowNegativeValues {
                return control * -1 * pitchRate
            }
        } else {
            if control >= 0 {
                return pow(control, 2) * -1 * pitchRate * ((control > 0) ? 1 : -1)
            }
        }
        
        return 0
    }
    
    private func roll(from control: Float) -> Float {
        if LINEAR_PR {
            if control >= 0
                || allowNegativeValues {
                return control * pitchRate
            }
        } else {
            if control >= 0 {
                return pow(control, 2) * pitchRate * ((control > 0) ? 1 : -1)
            }
        }
        
        return 0
    }
    
    private func yaw(from control: Float) -> Float {
        return control * yawRate
    }

    private func thrust(from control: Float) -> Float {
        var thrust: Float = 0
        if LINEAR_THRUST {
            thrust = control * 65535 * (maxThrust / 100)
        } else {
            thrust = sqrt(control) * 65535 * (maxThrust / 100)
        }
        if thrust > 65535 { thrust = 65535 }
        if thrust < 0 { thrust = 0 }
        return thrust
    
    }
}

final class SafeLandingCrazyFlieCommander: CrazyFlieCommander {
    private struct LandingSession {
        let startedAt: Date
        let initialThrust: Float
        let thrustPerSecond: Float
    }

    private let wrappedCommander: CrazyFlieCommander
    private let maxThrustValue: Float = 65535

    private var landingSession: LandingSession?
    private var hadDualThumbControl = false
    private var previousBothThumbsActive = false
    private var lastManualRoll: Float = 0
    private var lastManualPitch: Float = 0
    private var lastManualYaw: Float = 0
    private var lastManualThrust: Float = 0

    var onStateChanged: (() -> Void)?
    var onLandingCompleted: (() -> Void)?

    init(wrapping commander: CrazyFlieCommander) {
        self.wrappedCommander = commander
    }

    var pitch: Float = 0
    var roll: Float = 0
    var thrust: Float = 0
    var yaw: Float = 0

    var isSafeLandingActive: Bool {
        return landingSession != nil
    }

    func prepareData() {
        wrappedCommander.prepareData()

        if let landingSession = landingSession {
            let elapsed = Float(Date().timeIntervalSince(landingSession.startedAt))
            let currentThrust = max(0, landingSession.initialThrust - (landingSession.thrustPerSecond * elapsed))

            roll = 0
            pitch = 0
            yaw = 0
            thrust = currentThrust

            if currentThrust <= 0 {
                finishLanding()
            }
            return
        }

        roll = wrappedCommander.roll
        pitch = wrappedCommander.pitch
        yaw = wrappedCommander.yaw
        thrust = wrappedCommander.thrust

        lastManualRoll = roll
        lastManualPitch = pitch
        lastManualYaw = yaw
        lastManualThrust = thrust
    }

    func updateThumbState(leftActive: Bool, rightActive: Bool) {
        let bothThumbsActive = leftActive && rightActive
        if bothThumbsActive {
            hadDualThumbControl = true
        }

        let fingerReleasedDuringControl = previousBothThumbsActive && !bothThumbsActive
        previousBothThumbsActive = bothThumbsActive

        if SafeLandingSettings.isEnabled && fingerReleasedDuringControl && hadDualThumbControl && !isSafeLandingActive {
            startLanding()
        }
    }

    func resetSession() {
        landingSession = nil
        hadDualThumbControl = false
        previousBothThumbsActive = false
        pitch = 0
        roll = 0
        yaw = 0
        thrust = 0
        lastManualRoll = 0
        lastManualPitch = 0
        lastManualYaw = 0
        lastManualThrust = 0
        onStateChanged?()
    }

    private func startLanding() {
        let maxLandingThrust = maxThrustValue * SafeLandingSettings.maxStartPercent
        let startThrust = min(lastManualThrust, maxLandingThrust)
        let thrustPerSecond = maxLandingThrust / SafeLandingSettings.duration

        roll = 0
        pitch = 0
        yaw = 0
        thrust = max(0, startThrust)
        landingSession = LandingSession(startedAt: Date(),
                                        initialThrust: max(0, startThrust),
                                        thrustPerSecond: thrustPerSecond)
        onStateChanged?()

        if startThrust <= 0 {
            finishLanding()
        }
    }

    private func finishLanding() {
        landingSession = nil
        roll = 0
        pitch = 0
        yaw = 0
        thrust = 0
        hadDualThumbControl = false
        previousBothThumbsActive = false
        onStateChanged?()
        onLandingCompleted?()
    }
}
