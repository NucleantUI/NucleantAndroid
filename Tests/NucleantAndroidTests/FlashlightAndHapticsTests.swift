import Testing
@testable import AndroidFlashlight
@testable import AndroidHaptics

@Suite struct FlashlightTests {
    @Test func brightnessMapsOntoTorchLevels() {
        #expect(AFlashlight.level(forBrightness: 1, maximumLevel: 10) == 10)
        #expect(AFlashlight.level(forBrightness: 0.5, maximumLevel: 10) == 5)
        #expect(AFlashlight.level(forBrightness: 0.51, maximumLevel: 10) == 6)
        #expect(AFlashlight.level(forBrightness: 0, maximumLevel: 10) == 1)
    }

    @Test func brightnessOutsideTheRangeIsClamped() {
        #expect(AFlashlight.level(forBrightness: -3, maximumLevel: 4) == 1)
        #expect(AFlashlight.level(forBrightness: 9, maximumLevel: 4) == 4)
        #expect(AFlashlight.level(forBrightness: 0.2, maximumLevel: 1) == 1)
    }
}

@Suite struct HapticsTests {
    @Test func intensityMapsOntoAmplitude() {
        #expect(AVibrator.amplitude(forIntensity: 1) == 255)
        #expect(AVibrator.amplitude(forIntensity: 0.5) == 128)
        // 0 would mean "off" in a waveform; a one-shot at 0 is the weakest there is.
        #expect(AVibrator.amplitude(forIntensity: 0) == 1)
        #expect(AVibrator.amplitude(forIntensity: 7) == 255)
    }

    @Test func effectsUseAndroidsIDs() {
        #expect(AHapticEffect.click.effectID == 0)
        #expect(AHapticEffect.doubleClick.effectID == 1)
        #expect(AHapticEffect.tick.effectID == 2)
        #expect(AHapticEffect.heavyClick.effectID == 5)
    }
}
