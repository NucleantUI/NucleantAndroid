import Testing
@testable import AndroidBattery
@testable import AndroidBiometrics
@testable import AndroidDevice
@testable import AndroidLocation
@testable import AndroidNetwork
@testable import AndroidSensors

@Suite struct BatteryTests {
    @Test func levelIsRawOverScale() {
        #expect(ABattery.level(raw: 50, scale: 100) == 0.5)
        #expect(ABattery.level(raw: 3, scale: 4) == 0.75)
        #expect(ABattery.level(raw: -1, scale: 100) == nil)
        #expect(ABattery.level(raw: 50, scale: 0) == nil)
        #expect(ABattery.level(raw: 120, scale: 100) == 1)
    }

    @Test func extrasMapOntoStates() {
        #expect(ABatteryState(status: 2) == .charging)
        #expect(ABatteryState(status: 3) == .discharging)
        #expect(ABatteryState(status: 4) == .notCharging)
        #expect(ABatteryState(status: 5) == .full)
        #expect(ABatteryState(status: 1) == .unknown)
        #expect(APowerSource(plugged: 0) == .battery)
        #expect(APowerSource(plugged: 1) == .ac)
        #expect(APowerSource(plugged: 2) == .usb)
        #expect(APowerSource(plugged: 4) == .wireless)
        #expect(ABatteryHealth(health: 2) == .good)
        #expect(ABatteryHealth(health: 3) == .overheat)
    }
}

@Suite struct LocationTests {
    @Test func authorizationFromTheTwoPermissions() {
        #expect(ALocation.authorization(fine: true, coarse: true) == .precise)
        #expect(ALocation.authorization(fine: false, coarse: true) == .approximate)
        #expect(ALocation.authorization(fine: false, coarse: false) == .denied)
    }

    @Test func providerPrefersFusedThenGPSThenNetwork() {
        #expect(ALocation.provider(among: ["gps", "network", "fused", "passive"], precise: true) == "fused")
        #expect(ALocation.provider(among: ["gps", "network", "passive"], precise: true) == "gps")
        #expect(ALocation.provider(among: ["gps", "network"], precise: false) == "network")
        #expect(ALocation.provider(among: ["gps", "passive"], precise: false) == nil)
        #expect(ALocation.provider(among: [], precise: true) == nil)
    }
}

@Suite struct SensorTests {
    @Test func typesMapOntoKindsWithUnits() {
        #expect(ASensorKind(type: 1) == .accelerometer)
        #expect(ASensorKind(type: 4) == .gyroscope)
        #expect(ASensorKind(type: 5) == .light)
        #expect(ASensorKind(type: 65_536) == .other(65_536))
        #expect(ASensorKind.accelerometer.unit == "m/s²")
        #expect(ASensorKind.light.unit == "lx")
    }

    @Test func ratesAreSensorManagersDelays() {
        #expect(ASensorRate.fastest.samplingPeriod == 0)
        #expect(ASensorRate.game.samplingPeriod == 1)
        #expect(ASensorRate.ui.samplingPeriod == 2)
        #expect(ASensorRate.normal.samplingPeriod == 3)
    }
}

@Suite struct NetworkTests {
    @Test func transportsUseAndroidsIDs() {
        #expect(ANetworkTransport.cellular.transportID == 0)
        #expect(ANetworkTransport.wifi.transportID == 1)
        #expect(ANetworkTransport.ethernet.transportID == 3)
        #expect(ANetworkTransport.vpn.transportID == 4)
    }
}

@Suite struct DeviceTests {
    @Test func recognisesTheEmulator() {
        #expect(ADevice.looksLikeEmulator(
            fingerprint: "google/sdk_gphone64_x86_64/emu64xa:16/BP22.250325.006/13344233:user/release-keys",
            hardware: "ranchu", product: "sdk_gphone64_x86_64"))
        #expect(!ADevice.looksLikeEmulator(
            fingerprint: "google/husky/husky:15/AP4A.250105.002/12701944:user/release-keys",
            hardware: "husky", product: "husky"))
    }
}

@Suite struct BiometricsTests {
    @Test func codesMapOntoAvailability() {
        #expect(ABiometricAvailability(code: 0) == .available)
        #expect(ABiometricAvailability(code: 11) == .noneEnrolled)
        #expect(ABiometricAvailability(code: 12) == .noHardware)
        #expect(ABiometricAvailability(code: 1) == .unavailable)
        #expect(ABiometricAvailability(code: 99) == .unknown(99))
    }
}
