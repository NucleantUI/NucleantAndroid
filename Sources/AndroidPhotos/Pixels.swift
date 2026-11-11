//
//  Pixels.swift
//  AndroidPhotos
//
//  Decoding an image to pixels: BitmapFactory into an ARGB_8888 Bitmap, turned
//  upright, then copied straight into Swift memory (Bitmap.copyPixelsToBuffer
//  into a direct ByteBuffer over a Swift array).
//

import AndroidCore
import SwiftJava

/// Decoded pixels: 8-bit RGBA, alpha premultiplied, rows top to bottom.
public final class APixelBuffer: Sendable {
    public let width: Int
    public let height: Int
    /// Bytes from the start of one row to the next (at least `width * 4`).
    public let bytesPerRow: Int
    public let pixels: [UInt8]

    init(width: Int, height: Int, bytesPerRow: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.pixels = pixels
    }

    /// The pixel at (`x`, `y`), as RGBA.
    public func rgba(x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        let offset = y * bytesPerRow + x * 4
        return (pixels[offset], pixels[offset + 1], pixels[offset + 2], pixels[offset + 3])
    }
}

/// Decode `data` (a JPEG, PNG, HEIF, WebP… file) to pixels at most
/// `maxPixelSize` on its longer side, rotated clockwise by `rotation` degrees.
/// On the calling thread.
func decodePixels(_ data: [UInt8], maxPixelSize: Int, rotation: Int) throws -> APixelBuffer {
    let environment = try JavaVirtualMachine.shared().environment()
    let factory = try JavaClass<BitmapFactory>(environment: environment)

    let bounds = BitmapFactoryOptions(environment: environment)
    bounds.inJustDecodeBounds = true
    _ = factory.decodeByteArray(data, 0, Int32(data.count), bounds)
    guard bounds.outWidth > 0, bounds.outHeight > 0 else {
        throw APhotoLibraryError.decodingFailed
    }

    let options = BitmapFactoryOptions(environment: environment)
    options.inSampleSize = Int32(sampleSize(width: Int(bounds.outWidth), height: Int(bounds.outHeight), maxPixelSize: maxPixelSize))
    options.inPreferredConfig = try JavaClass<BitmapConfig>(environment: environment).ARGB_8888
    guard var bitmap = factory.decodeByteArray(data, 0, Int32(data.count), options) else {
        throw APhotoLibraryError.decodingFailed
    }
    if rotation % 360 != 0 {
        let matrix = Matrix(environment: environment)
        _ = matrix.postRotate(Float(rotation))
        if let rotated = try JavaClass<Bitmap>(environment: environment).createBitmap(
            bitmap, 0, 0, bitmap.getWidth(), bitmap.getHeight(), matrix, true)
        {
            bitmap.recycle()
            bitmap = rotated
        }
    }
    defer { bitmap.recycle() }

    var pixels = [UInt8](repeating: 0, count: Int(bitmap.getByteCount()))
    try pixels.withUnsafeMutableBytes { raw in
        guard let buffer = environment.interface.NewDirectByteBuffer(environment, raw.baseAddress, Int64(raw.count)) else {
            throw APhotoLibraryError.decodingFailed
        }
        try bitmap.copyPixelsToBuffer(JavaNioBufferObject(javaThis: buffer, environment: environment))
    }
    return APixelBuffer(
        width: Int(bitmap.getWidth()),
        height: Int(bitmap.getHeight()),
        bytesPerRow: Int(bitmap.getRowBytes()),
        pixels: pixels
    )
}

/// The power of two BitmapFactory subsamples by, so the longer side stays at
/// least `maxPixelSize` (it never upsamples).
func sampleSize(width: Int, height: Int, maxPixelSize: Int) -> Int {
    var sample = 1
    while max(width, height) / (sample * 2) >= max(maxPixelSize, 1) {
        sample *= 2
    }
    return sample
}

// MARK: - Framework

/// `android.graphics.BitmapFactory`.
@JavaClass("android.graphics.BitmapFactory")
open class BitmapFactory: JavaObject {}

extension JavaClass<BitmapFactory> {
    @JavaStaticMethod
    public func decodeByteArray(_ data: [UInt8], _ offset: Int32, _ length: Int32, _ options: BitmapFactoryOptions?) -> Bitmap!
}

/// `android.graphics.BitmapFactory.Options`.
@JavaClass("android.graphics.BitmapFactory$Options")
open class BitmapFactoryOptions: JavaObject {
    @JavaMethod
    @_nonoverride public convenience init(environment: JNIEnvironment? = nil)

    @JavaField public var inJustDecodeBounds: Bool
    @JavaField public var inSampleSize: Int32
    @JavaField public var inPreferredConfig: BitmapConfig?
    @JavaField public var outWidth: Int32
    @JavaField public var outHeight: Int32
}

/// `android.graphics.Bitmap.Config` (an enum; its constants are static fields).
@JavaClass("android.graphics.Bitmap$Config")
open class BitmapConfig: JavaObject {}

extension JavaClass<BitmapConfig> {
    @JavaStaticField(isFinal: true)
    public var ARGB_8888: BitmapConfig!
}

/// `android.graphics.Matrix`.
@JavaClass("android.graphics.Matrix")
open class Matrix: JavaObject {
    @JavaMethod
    @_nonoverride public convenience init(environment: JNIEnvironment? = nil)

    @JavaMethod
    open func postRotate(_ degrees: Float) -> Bool
}

/// `java.nio.Buffer`, for `Bitmap.copyPixelsToBuffer`.
@JavaClass("java.nio.Buffer")
open class JavaNioBufferObject: JavaObject {}
