//
//  ShareSheet.swift
//  AndroidShare
//
//  Android's share sheet (the chooser over `ACTION_SEND`), for text and for
//  images already in MediaStore or behind any other content:// URI the app
//  can read. No permission needed; the receiving app gets read access to a
//  shared URI for as long as it needs it.
//

import AndroidCore
import Observation
import SwiftJava

/// The share sheet. Use it on the main thread: it is shown over the attached
/// Activity.
@Observable
public final class AShareSheet: @unchecked Sendable {
    /// What the sheet is titled when no other title is given.
    public let defaultTitle: String

    public init(defaultTitle: String = "Share") {
        self.defaultTitle = defaultTitle
    }

    /// Offer `text` to the apps that take text.
    public func share(text: String, title: String? = nil) throws {
        let environment = try JavaVirtualMachine.shared().environment()
        let intent = Intent(Self.actionSend, environment: environment)
        _ = intent.setType("text/plain")
        _ = intent.putExtra(Self.extraText, JavaString(text, environment: environment))
        try present(intent, title: title, in: environment)
    }

    /// Offer the file behind `uri` (an `APhotoAsset.uri`, for one) to the apps
    /// that take `mimeType`.
    public func share(uri: Uri, mimeType: String, title: String? = nil) throws {
        let environment = try JavaVirtualMachine.shared().environment()
        let intent = Intent(Self.actionSend, environment: environment)
        _ = intent.setType(mimeType)
        _ = intent.putExtra(Self.extraStream, try uri.boundToCurrentThread().as(Parcelable.self))
        _ = intent.addFlags(Self.flagGrantReadURIPermission)
        try present(intent, title: title, in: environment)
    }

    private func present(_ intent: Intent, title: String?, in environment: JNIEnvironment) throws {
        let chooser = try JavaClass<Intent>(environment: environment)
            .createChooser(intent, charSequence(title ?? defaultTitle, in: environment))
        try AndroidContext.shared.activity(in: environment).startActivity(chooser)
    }

    static let actionSend = "android.intent.action.SEND"
    static let extraText = "android.intent.extra.TEXT"
    static let extraStream = "android.intent.extra.STREAM"
    static let flagGrantReadURIPermission: Int32 = 1
}
