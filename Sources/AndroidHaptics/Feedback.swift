//
//  Feedback.swift
//  AndroidHaptics
//
//  The system's standard haptic feedback — the tap, confirm and reject the
//  system UI uses itself — through `View.performHapticFeedback` on the
//  attached Activity's window. Unlike the vibrator, it follows the user's
//  "touch feedback" setting, and the device's tuning of each kind.
//

import AndroidCore
import SwiftJava

/// Standard feedback kinds: `HapticFeedbackConstants`.
public enum AHapticFeedback: Int32, Sendable, CaseIterable {
    /// A key or button press (`VIRTUAL_KEY`).
    case tap = 1
    case longPress = 0
    case contextClick = 6
    /// A detent: a dial or picker passing a step (`CLOCK_TICK`).
    case tick = 4
    /// Something completed (`CONFIRM`, Android 11+; a click before).
    case success = 16
    /// Something was refused (`REJECT`, Android 11+; a heavy click before).
    case error = 17
    /// A drag or swipe starting / ending (Android 11+).
    case gestureStart = 12
    case gestureEnd = 13
    /// A switch turned on / off (Android 14+).
    case toggleOn = 21
    case toggleOff = 22

    /// The first Android with the constant.
    var minimumSDK: Int {
        switch self {
        case .tap, .longPress, .contextClick, .tick: 23
        case .success, .error, .gestureStart, .gestureEnd: 30
        case .toggleOn, .toggleOff: 34
        }
    }

    /// What plays on an Android without the constant.
    var fallback: AHapticEffect? {
        switch self {
        case .success: .click
        case .error: .heavyClick
        case .gestureStart, .gestureEnd, .toggleOn, .toggleOff: .tick
        default: nil
        }
    }
}

extension AVibrator {
    /// Play standard feedback on the attached Activity's window. On the main
    /// thread. False when the system skipped it (touch feedback off, or no
    /// window).
    @discardableResult
    public func perform(_ feedback: AHapticFeedback) throws -> Bool {
        let environment = try JavaVirtualMachine.shared().environment()
        if try AndroidContext.shared.sdkLevel(in: environment) < feedback.minimumSDK {
            guard let fallback = feedback.fallback else { return false }
            try play(fallback)
            return true
        }
        guard let view = try AndroidContext.shared.activity(in: environment).getWindow()?.getDecorView() else {
            return false
        }
        return view.performHapticFeedback(feedback.rawValue)
    }
}

// MARK: - Framework

extension Window {
    @JavaMethod
    func getDecorView() -> FeedbackView!
}

/// `android.view.View`: what feedback needs of it.
@JavaClass("android.view.View")
open class FeedbackView: JavaObject {
    @JavaMethod
    open func performHapticFeedback(_ feedbackConstant: Int32) -> Bool
}
