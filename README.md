# NucleantAndroid

The Android SDK in Swift, through [swift-java](https://github.com/swiftlang/swift-java)
0.4.2 (the version NucleantApplication uses). Each capability has its own
target, and each target is the Android side only. The cross-platform types
that put a capability next to its Apple side come later, in their own
package. So the types here carry Android's own `A` prefix (as in `ALooper`
and `ANativeWindow`), and the plain names stay free.

| Target | Types | Android API |
|---|---|---|
| `AndroidFlashlight` | `AFlashlight`: on/off, brightness levels, follows the torch wherever it is switched | `CameraManager` torch mode + `TorchCallback` |
| `AndroidCamera` | `ACameras`, `ACamera`, `APhoto`: cameras, access, live preview into a `SurfaceTexture`, taking a JPEG (from the preview, or cold) | Camera2 |
| `AndroidPhotos` | `APhotoLibrary`, `APhotoAsset`, `APickedImage`, `APixelBuffer`: access, newest photos (kept current), data, thumbnails, decoding to RGBA pixels, saving, the photo picker, the camera app | MediaStore + `ContentObserver`, `PICK_IMAGES`, `IMAGE_CAPTURE`, BitmapFactory |
| `AndroidFiles` | `AAppFiles`, `ADocuments`, `ADocument`: the app's own directory (list/read/write/delete/usage), the system open and save pickers | `java.io.File`, Storage Access Framework |
| `AndroidHaptics` | `AVibrator`: timed vibrations, patterns, system haptic effects, standard feedback (tap, success, error, …) | `Vibrator`, `VibrationEffect`, `View.performHapticFeedback` |
| `AndroidBattery` | `ABattery`: level, charging, power source, health, temperature, battery saver | `ACTION_BATTERY_CHANGED`, `PowerManager` |
| `AndroidSensors` | `ASensors`, `ASensor`: every sensor, live readings at a chosen rate, the step sensors' permission | `SensorManager` |
| `AndroidLocation` | `ALocation`, `ALocationFix`, `AAddress`: access (precise/approximate), last known, one fix, continuous updates, reverse geocoding | `LocationManager`, `Geocoder` |
| `AndroidClipboard` | `AClipboard`: text, follows changes from any app | `ClipboardManager` |
| `AndroidNetwork` | `ANetwork`: connected, validated, metered, transports, bandwidth | `ConnectivityManager` default-network callback |
| `AndroidNotifications` | `ANotifications`, `ANotificationChannel`: permission, channels, post, update, cancel, which one was tapped (no remote push) | `NotificationManager` |
| `AndroidShare` | `AShareSheet`: share text or any content:// URI | `ACTION_SEND` chooser |
| `AndroidDevice` | `ADevice`: build, screen, memory, keep-screen-on, window brightness | `Build`, `DisplayMetrics`, `ActivityManager`, `Window` |
| `AndroidSpeech` | `ATextToSpeech`: speak, stop, rate, pitch | `TextToSpeech` |
| `AndroidBiometrics` | `ABiometrics`: availability, the biometric prompt | `BiometricManager`, `BiometricPrompt` |
| `AndroidCore` | `AndroidContext` (the host's Activity, permissions, activity results, new intents), `AndroidMainThread`, `NativeHandle`, shared framework wrappers | |

Every capability type is an `@Observable final class` that keeps its
swift-java objects (`CameraManager`, `CameraCharacteristics`, `Uri`, …) and
changes through its own methods. Where Android reports changes, the class
registers for them, so the observable state follows the device: the torch,
the battery, the network, the clipboard, MediaStore, sensors and location.
Nothing depends on NucleantUI or NucleantApplication.

## Using it

The host hands its Activity over once, and forwards what Android delivers to
the Activity only: permission answers, activity results (the pickers and the
camera app answer there) and new intents (a tapped notification; declare the
Activity `singleTop`):

```kotlin
override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    DeviceLabBridge.attachActivity(this)          // → AndroidContext.shared.attach(activity:)
}

override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
    if (!DeviceLabBridge.permissionsResult(requestCode, permissions, grantResults))  // → handlePermissionsResult
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
}

override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
    if (!DeviceLabBridge.activityResult(requestCode, resultCode, Optional.ofNullable(data)))  // → handleActivityResult
        super.onActivityResult(requestCode, resultCode, data)
}

override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    DeviceLabBridge.newIntent(intent)                // → handleNewIntent
}
```

From then on it is Swift:

```swift
if let flashlight = try AFlashlight() {
    try flashlight.turnOn(brightness: 0.5)        // flashlight.isOn, .level: observable
}

let cameras = try ACameras()
if try await cameras.requestAccess(), let back = cameras.all.first(where: { $0.position == .back }) {
    let photo = try await back.takePhoto()        // back.isCapturing, .lastPhoto: observable
    try await APhotoLibrary(album: "My App").save(jpeg: photo.jpegData, name: "photo.jpg", rotation: photo.rotation)
}
```

**Threads.** Create the classes on the main thread and use them there.
Android delivers its callbacks there too: every listener is registered with
a main-Looper Handler. `async` methods (taking a photo, asking for a
permission, loading a thumbnail) can be called from anywhere. They do their
work where it belongs and update the observable state on the main thread.
A swift-java wrapper is bound to the thread that made it. Code that moves one
to another thread re-binds it (`boundToCurrentThread()`) or carries a
`JavaGlobalReference`.

**Callbacks.** Android reports through listener objects and abstract
classes, which Swift cannot subclass. `Android/java` holds a small Java helper
for each one. The helper carries a `NativeHandle` and forwards every callback
to a `static native` method implemented in Swift with `@JavaImplementation`.
The handle refers to its Swift owner weakly. When the owner goes away, its
`deinit` disarms the helper, unregisters it and releases the handle on the
main thread, so a late callback never reaches freed memory.
`NativeMethodBindingTests` checks that every `native` in `Android/java` has
its Swift symbol.

An app compiles `Android/java` together with its own Java and declares the
permissions it uses. The Device Lab manifest has the full list.

## Device Lab

`Demo/` is a Kotlin app with one card per target. Its Swift is the
`DeviceLabBridge` target, which jextract turns into Java
(`org.nucleantui.devicelab.bridge`). Each card follows its Swift model through
`observe(Runnable)`, which tracks the model with `withObservationTracking` and
runs the Runnable on the main thread after every change.
`Demo/app/build.gradle.kts` does three things:

- cross-compiles the bridge per ABI with the Swift Android SDK;
- stages `libDeviceLabBridge.so` and the Swift runtime libraries it links
  into `jniLibs`;
- adds the generated Java, swift-java's SwiftKitCore and `Android/java` to
  the app's sources.

```sh
uv run scripts/run_device_lab.py --logcat
```

The script creates a `DeviceLab` AVD from the newest installed system image,
with emulated cameras. It boots the AVD unless a device is already connected,
then builds, installs and launches the app. Each card says how to drive its
capability from the emulator's Extended controls or `adb emu`: the battery,
location, virtual sensors, a fingerprint, the network.

Requirements: the Android SDK with NDK r27d or later, a JDK 17+, and the
Swift Android SDK for the toolchain in use:

```sh
swift sdk install https://download.swift.org/swift-6.3.3-release/android-sdk/swift-6.3.3-RELEASE/swift-6.3.3-RELEASE_android.artifactbundle.tar.gz \
  --checksum d160cc3206dd1886dae3fef2337af5e25ec034692cd0ec225721c56cc69da7f5
ANDROID_NDK_HOME=<android-sdk>/ndk/27.3.13750724 \
  ~/Library/org.swift.swiftpm/swift-sdks/swift-6.3.3-RELEASE_android.artifactbundle/swift-android/scripts/setup-android-sdk.sh
```

## Developing

The whole package also builds on the host, because swift-java only looks Java
classes up at run time. `swift build` and `swift test` work on macOS, and so
does the editor's LSP. Calling the APIs only means something inside an Android
process.
