//
//  TextToSpeech.swift
//  AndroidSpeech
//
//  Speaking text aloud with the device's text-to-speech engine. No permission
//  needed. The engine starts up asynchronously: `isReady` turns true (or
//  `initializationFailed` does) once it is.
//
//  Emulator images ship an engine (Google's on Google APIs images); the sound
//  goes to the host's speakers.
//

import AndroidCore
import Observation
import SwiftJava

/// The text-to-speech engine. Create and use it on the main thread; its state
/// changes there.
@Observable
public final class ATextToSpeech: @unchecked Sendable {
    /// Whether the engine is up and `speak(_:)` works.
    public private(set) var isReady = false
    /// Whether the engine failed to start (no engine installed, for one).
    public private(set) var initializationFailed = false
    public private(set) var isSpeaking = false
    /// The id `speak(_:)` returned for what is being spoken.
    public private(set) var currentUtterance: String?
    /// The engine's package name, once ready.
    public private(set) var engine: String?
    /// 1 is normal speed.
    public private(set) var rate: Float = 1
    /// 1 is normal pitch.
    public private(set) var pitch: Float = 1

    @ObservationIgnored private var textToSpeech: TextToSpeech?
    @ObservationIgnored private var callbacks: SpeechCallbacks?
    @ObservationIgnored private var handle: Int64 = 0
    @ObservationIgnored private var nextUtterance = 1

    public init() throws {
        let environment = try JavaVirtualMachine.shared().environment()
        let context = try AndroidContext.shared.applicationContext(in: environment)
        let handle = NativeHandle.retain(self)
        let callbacks = SpeechCallbacks(handle, environment: environment)
        self.handle = handle
        self.callbacks = callbacks
        let textToSpeech = TextToSpeech(context, callbacks.as(TextToSpeechOnInitListener.self), environment: environment)
        self.textToSpeech = textToSpeech
        _ = textToSpeech.setOnUtteranceProgressListener(callbacks)
    }

    deinit {
        guard let callbacks, let textToSpeech else { return }
        let speechCallbacks = JavaGlobalReference(callbacks)
        let engine = JavaGlobalReference(textToSpeech)
        let handle = self.handle
        try? AndroidMainThread.shared.post { environment in
            // disarm() waits out a callback in progress on the binder thread.
            speechCallbacks.wrapped(as: SpeechCallbacks.self, in: environment).disarm()
            engine.wrapped(as: TextToSpeech.self, in: environment).shutdown()
            NativeHandle<ATextToSpeech>.release(handle)
        }
    }

    /// Speak `text`, cutting off whatever is being spoken (or after it, with
    /// `interrupting: false`). Returns the utterance's id.
    @discardableResult
    public func speak(_ text: String, interrupting: Bool = true) throws -> String {
        guard isReady, let textToSpeech else {
            throw ASpeechError.notReady
        }
        let environment = try JavaVirtualMachine.shared().environment()
        let id = "utterance-\(nextUtterance)"
        nextUtterance += 1
        let result = textToSpeech.speak(
            charSequence(text, in: environment), interrupting ? 0 : 1, nil, id) // QUEUE_FLUSH / QUEUE_ADD
        guard result == 0 else { // TextToSpeech.SUCCESS
            throw ASpeechError.speakFailed
        }
        return id
    }

    public func stop() {
        _ = textToSpeech?.stop()
        isSpeaking = false
        currentUtterance = nil
    }

    /// 1 is normal; 0.5 half as fast, 2 twice.
    public func setRate(_ rate: Float) {
        _ = textToSpeech?.setSpeechRate(rate)
        self.rate = rate
    }

    /// 1 is normal; lower is deeper.
    public func setPitch(_ pitch: Float) {
        _ = textToSpeech?.setPitch(pitch)
        self.pitch = pitch
    }

    // MARK: - Callbacks (main thread)

    func initialized(status: Int32) {
        if status == 0 { // TextToSpeech.SUCCESS
            isReady = true
            engine = textToSpeech?.getDefaultEngine()
        } else {
            initializationFailed = true
        }
    }

    func utterance(_ id: String, event: Int32) {
        switch event {
        case 0:
            isSpeaking = true
            currentUtterance = id
        default:
            if currentUtterance == id {
                isSpeaking = false
                currentUtterance = nil
            }
        }
    }
}

public enum ASpeechError: Error, CustomStringConvertible {
    case notReady
    case speakFailed

    public var description: String {
        switch self {
        case .notReady: "The text-to-speech engine is not ready"
        case .speakFailed: "The text-to-speech engine did not accept the text"
        }
    }
}

// MARK: - Framework

/// `android.speech.tts.TextToSpeech`.
@JavaClass("android.speech.tts.TextToSpeech")
open class TextToSpeech: JavaObject {
    @JavaMethod
    @_nonoverride public convenience init(
        _ context: Context?, _ listener: TextToSpeechOnInitListener?, environment: JNIEnvironment? = nil)

    /// `speak(CharSequence, int, Bundle, String)`, API 21.
    @JavaMethod
    open func speak(_ text: CharSequence?, _ queueMode: Int32, _ params: Bundle?, _ utteranceId: String) -> Int32

    @JavaMethod
    open func stop() -> Int32

    @JavaMethod
    open func shutdown()

    @JavaMethod
    open func setSpeechRate(_ speechRate: Float) -> Int32

    @JavaMethod
    open func setPitch(_ pitch: Float) -> Int32

    @JavaMethod
    open func getDefaultEngine() -> String

    @JavaMethod
    open func setOnUtteranceProgressListener(_ listener: UtteranceProgressListener?) -> Int32
}

/// `android.speech.tts.TextToSpeech.OnInitListener`.
@JavaInterface("android.speech.tts.TextToSpeech$OnInitListener")
public struct TextToSpeechOnInitListener {}

/// `android.speech.tts.UtteranceProgressListener`.
@JavaClass("android.speech.tts.UtteranceProgressListener")
open class UtteranceProgressListener: JavaObject {}

// MARK: - SpeechCallbacks (Android/java)

@JavaClass("org.nucleantui.android.speech.SpeechCallbacks", implements: TextToSpeechOnInitListener.self)
class SpeechCallbacks: UtteranceProgressListener {
    @JavaMethod
    convenience init(_ handle: Int64, environment: JNIEnvironment? = nil)

    @JavaMethod
    func disarm()
}

@JavaImplementation("org.nucleantui.android.speech.SpeechCallbacks")
extension SpeechCallbacks {
    @JavaMethod
    static func nativeOnInit(_ handle: Int64, _ status: Int32, environment: JNIEnvironment) {
        guard let speech = NativeHandle<ATextToSpeech>.owner(handle) else { return }
        try? AndroidMainThread.shared.post { _ in speech.initialized(status: status) }
    }

    /// On a TTS binder thread: state changes go to the main thread.
    @JavaMethod
    static func nativeOnUtterance(_ handle: Int64, _ utteranceId: String, _ event: Int32, environment: JNIEnvironment) {
        guard let speech = NativeHandle<ATextToSpeech>.owner(handle) else { return }
        try? AndroidMainThread.shared.post { _ in speech.utterance(utteranceId, event: event) }
    }
}
