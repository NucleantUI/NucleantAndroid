//
//  Every `native` method declared by the Java helpers in Android/java must have
//  a Swift implementation exported under its JNI name — otherwise the first
//  call from Java fails with UnsatisfiedLinkError, which only an Android
//  device would show. The `@JavaImplementation` symbols are linked into this
//  test bundle with the targets, so they are looked up here.
//

import Foundation
import Testing
@testable import AndroidCore

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@Suite struct NativeMethodBindingTests {
    /// Android/java, found from this file's path.
    static let javaRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Android/java")

    struct NativeMethod: CustomStringConvertible {
        let className: String
        let methodName: String

        /// The JNI short name: `Java_` + mangled class + `_` + mangled method.
        var symbol: String {
            "Java_" + className.split(separator: ".").map { Self.mangle(String($0)) }.joined(separator: "_")
                + "_" + Self.mangle(methodName)
        }

        var description: String { "\(className).\(methodName)" }

        static func mangle(_ name: String) -> String {
            name.map { $0 == "_" ? "_1" : String($0) }.joined()
        }
    }

    static func nativeMethods() throws -> [NativeMethod] {
        let files = FileManager.default.enumerator(at: javaRoot, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "java" } ?? []
        let packagePattern = try Regex(#"^package\s+([\w.]+)\s*;"#).anchorsMatchLineEndings()
        let nativePattern = try Regex(#"\bnative\s+[\w.\[\]<>]+\s+(\w+)\s*\("#)

        var methods: [NativeMethod] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            guard let package = source.firstMatch(of: packagePattern)?.output[1].substring else { continue }
            let className = "\(package).\(file.deletingPathExtension().lastPathComponent)"
            for match in source.matches(of: nativePattern) {
                if let name = match.output[1].substring {
                    methods.append(NativeMethod(className: className, methodName: String(name)))
                }
            }
        }
        return methods
    }

    @Test func javaHelpersDeclareNativeMethods() throws {
        // Guards the test itself: a wrong path would find nothing and pass.
        let methods = try Self.nativeMethods()
        #expect(methods.count >= 24)
        #expect(methods.contains { $0.className == "org.nucleantui.android.NativeRunnable" })
    }

    @Test func everyNativeMethodHasItsSymbol() throws {
        var info = Dl_info()
        #expect(dladdr(#dsohandle, &info) != 0)
        let image = try #require(dlopen(info.dli_fname, RTLD_NOW | RTLD_NOLOAD))
        defer { dlclose(image) }

        for method in try Self.nativeMethods() {
            #expect(dlsym(image, method.symbol) != nil, "no Swift implementation of \(method) (\(method.symbol))")
        }
    }
}
