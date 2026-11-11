//
//  Clipboard.swift
//  AndroidClipboard
//
//  The system clipboard's text, through ClipboardManager, kept current as it
//  changes — from this app or any other. No permission needed, but Android 10+
//  only lets the app in front read it, and Android 12+ shows a "pasted"
//  notice when it does.
//

import AndroidCore
import Observation
import SwiftJava

/// The clipboard. Create and use it on the main thread, where changes arrive.
@Observable
public final class AClipboard: @unchecked Sendable {
    /// The clipboard's text; nil when it holds none.
    public private(set) var text: String?
    /// How many times it has changed since this object was made.
    public private(set) var changeCount = 0

    @ObservationIgnored private let manager: ClipboardManager
    @ObservationIgnored private let context: Context
    @ObservationIgnored private var listener: ClipChangedListener?
    @ObservationIgnored private var handle: Int64 = 0

    public init() throws {
        let environment = try JavaVirtualMachine.shared().environment()
        let context = try AndroidContext.shared.applicationContext(in: environment)
        guard let manager = context.getSystemService("clipboard")?.as(ClipboardManager.self) else {
            throw AndroidError.serviceUnavailable("clipboard")
        }
        self.manager = manager
        self.context = context
        let handle = NativeHandle.retain(self)
        let listener = ClipChangedListener(handle, environment: environment)
        self.handle = handle
        self.listener = listener
        manager.addPrimaryClipChangedListener(listener.clipListener)
        refresh()
    }

    deinit {
        guard let listener else { return }
        let changedListener = JavaGlobalReference(listener)
        let manager = JavaGlobalReference(self.manager)
        let handle = self.handle
        try? AndroidMainThread.shared.post { environment in
            let listener = changedListener.wrapped(as: ClipChangedListener.self, in: environment)
            listener.disarm()
            manager.wrapped(as: ClipboardManager.self, in: environment).removePrimaryClipChangedListener(listener.clipListener)
            NativeHandle<AClipboard>.release(handle)
        }
    }

    public var hasText: Bool {
        text != nil
    }

    /// Put `text` on the clipboard. `label` is the description the system
    /// shows for it (in its clipboard preview).
    public func setText(_ text: String, label: String = "Text") throws {
        let environment = try JavaVirtualMachine.shared().environment()
        let clip = try JavaClass<ClipData>(environment: environment).newPlainText(
            charSequence(label, in: environment), charSequence(text, in: environment))
        manager.setPrimaryClip(clip)
        self.text = text
    }

    /// Empty the clipboard. Android 9+.
    public func clear() {
        manager.clearPrimaryClip()
        text = nil
    }

    /// Read the clipboard again.
    public func refresh() {
        guard manager.hasPrimaryClip(), let clip = manager.getPrimaryClip(), clip.getItemCount() > 0,
              let item = clip.getItemAt(0)
        else {
            text = nil
            return
        }
        // coerceToText also turns a URI or an Intent into text.
        text = item.coerceToText(context)?.toString()
    }

    func changed() {
        changeCount += 1
        refresh()
    }
}

// MARK: - Framework

/// `android.content.ClipboardManager`.
@JavaClass("android.content.ClipboardManager")
open class ClipboardManager: JavaObject {
    @JavaMethod
    open func hasPrimaryClip() -> Bool

    @JavaMethod
    open func getPrimaryClip() -> ClipData!

    @JavaMethod
    open func setPrimaryClip(_ clip: ClipData?)

    /// API 28.
    @JavaMethod
    open func clearPrimaryClip()

    @JavaMethod
    open func addPrimaryClipChangedListener(_ listener: OnPrimaryClipChangedListener?)

    @JavaMethod
    open func removePrimaryClipChangedListener(_ listener: OnPrimaryClipChangedListener?)
}

/// `android.content.ClipboardManager.OnPrimaryClipChangedListener`.
@JavaInterface("android.content.ClipboardManager$OnPrimaryClipChangedListener")
public struct OnPrimaryClipChangedListener {}

/// `android.content.ClipData`.
@JavaClass("android.content.ClipData")
open class ClipData: JavaObject {
    @JavaMethod
    open func getItemCount() -> Int32

    @JavaMethod
    open func getItemAt(_ index: Int32) -> ClipDataItem!
}

extension JavaClass<ClipData> {
    @JavaStaticMethod
    public func newPlainText(_ label: CharSequence?, _ text: CharSequence?) -> ClipData!
}

/// `android.content.ClipData.Item`.
@JavaClass("android.content.ClipData$Item")
open class ClipDataItem: JavaObject {
    @JavaMethod
    open func coerceToText(_ context: Context?) -> CharSequence?
}

// MARK: - ClipChangedListener (Android/java)

@JavaClass("org.nucleantui.android.clipboard.ClipChangedListener", implements: OnPrimaryClipChangedListener.self)
class ClipChangedListener: JavaObject {
    @JavaMethod
    convenience init(_ handle: Int64, environment: JNIEnvironment? = nil)

    @JavaMethod
    func disarm()

    var clipListener: OnPrimaryClipChangedListener? { self.as(OnPrimaryClipChangedListener.self) }
}

@JavaImplementation("org.nucleantui.android.clipboard.ClipChangedListener")
extension ClipChangedListener {
    @JavaMethod
    static func nativeOnPrimaryClipChanged(_ handle: Int64, environment: JNIEnvironment) {
        NativeHandle<AClipboard>.owner(handle)?.changed()
    }
}
