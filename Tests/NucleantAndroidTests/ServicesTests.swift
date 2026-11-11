import Testing
@testable import AndroidCamera
@testable import AndroidFiles
@testable import AndroidHaptics
@testable import AndroidNotifications
@testable import AndroidPhotos

@Suite struct AppFilesTests {
    @Test func pathsStayInsideTheDirectory() {
        #expect(AAppFiles.isValid("notes.txt"))
        #expect(AAppFiles.isValid("notes/2026/today.txt"))
        #expect(!AAppFiles.isValid(""))
        #expect(!AAppFiles.isValid("/etc/hosts"))
        #expect(!AAppFiles.isValid("../shared_prefs/x.xml"))
        #expect(!AAppFiles.isValid("notes/../../x"))
        #expect(!AAppFiles.isValid("notes//x"))
        #expect(!AAppFiles.isValid("./x"))
    }
}

@Suite struct PixelsTests {
    @Test func subsamplingKeepsTheLongerSideAtLeastTheTarget() {
        #expect(sampleSize(width: 4032, height: 3024, maxPixelSize: 4032) == 1)
        #expect(sampleSize(width: 4032, height: 3024, maxPixelSize: 2016) == 2)
        #expect(sampleSize(width: 4032, height: 3024, maxPixelSize: 1000) == 4)
        #expect(sampleSize(width: 4032, height: 3024, maxPixelSize: 200) == 16)
        #expect(sampleSize(width: 100, height: 80, maxPixelSize: 4096) == 1)
    }
}

@Suite struct PreviewSizeTests {
    let streams = [(width: 320, height: 240), (width: 1280, height: 720), (width: 1440, height: 1080), (width: 1920, height: 1080), (width: 3840, height: 2160)]

    @Test func previewMatchesThePhotosAspectRatio() {
        // 4:3 photo → the largest 4:3 stream up to 1080p.
        #expect(ACamera.previewSizeIndex(in: streams, matching: (width: 4032, height: 3024)) == 2)
        // 16:9 photo → 1920×1080, not the 4K stream.
        #expect(ACamera.previewSizeIndex(in: streams, matching: (width: 3840, height: 2160)) == 3)
    }

    @Test func previewFallsBackToTheLargestThatFits() {
        #expect(ACamera.previewSizeIndex(in: streams, matching: (width: 1000, height: 1000)) == 3)
        #expect(ACamera.previewSizeIndex(in: [(width: 3840, height: 2160)], matching: (width: 4, height: 3)) == 0)
        #expect(ACamera.previewSizeIndex(in: [], matching: (width: 4, height: 3)) == nil)
    }
}

@Suite struct NotificationTests {
    @Test func importanceUsesAndroidsValues() {
        #expect(ANotificationImportance.none.value == 0)
        #expect(ANotificationImportance.low.value == 2)
        #expect(ANotificationImportance.default.value == 3)
        #expect(ANotificationImportance.high.value == 4)
        #expect(ANotificationImportance(value: 4) == .high)
        #expect(ANotificationImportance(value: -1000) == .default) // IMPORTANCE_UNSPECIFIED
    }
}

@Suite struct HapticFeedbackTests {
    @Test func feedbackUsesHapticFeedbackConstants() {
        #expect(AHapticFeedback.longPress.constant == 0)
        #expect(AHapticFeedback.tap.constant == 1)
        #expect(AHapticFeedback.success.constant == 16)
        #expect(AHapticFeedback.error.constant == 17)
        #expect(AHapticFeedback.toggleOn.constant == 21)
    }

    @Test func newerKindsFallBackOnOlderAndroids() {
        #expect(AHapticFeedback.success.minimumSDK == 30)
        #expect(AHapticFeedback.success.fallback == .click)
        #expect(AHapticFeedback.error.fallback == .heavyClick)
        #expect(AHapticFeedback.toggleOn.minimumSDK == 34)
        #expect(AHapticFeedback.tap.fallback == nil)
    }
}
