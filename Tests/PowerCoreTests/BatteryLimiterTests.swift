import Foundation
import XCTest
@testable import PowerCore

@objcMembers
public final class BatteryLimiterTests: XCTestCase {

    public func testBatteryTelemetryCalculations() throws {
        let telemetry = BatteryTelemetry(
            percentage: 80,
            maxCapacity: 100,
            isCharging: true,
            isPluggedIn: true,
            isFullyCharged: false,
            amperage: 1800,
            voltage: 13000,
            wattage: 23.4,
            cycleCount: 221,
            designCapacity: 4629,
            fullChargeCapacity: 3917,
            healthPercentage: 84.6,
            temperature: 31.0,
            timeRemainingMinutes: 45,
            powerSource: "Power Adapter",
            adapterWatts: 100,
            adapterName: "pd charger",
            chargingState: .charging,
            isBypassed: false
        )

        XCTAssertEqual(telemetry.percentage, 80)
        XCTAssertTrue(telemetry.isCharging)
        XCTAssertTrue(telemetry.isPluggedIn)
        XCTAssertEqual(telemetry.cycleCount, 221)
        XCTAssertEqual(telemetry.adapterWatts, 100)
        XCTAssertEqual(telemetry.healthPercentage, 84.6)
        XCTAssertEqual(telemetry.formattedRemainingTime, "45m until full")
        XCTAssertEqual(telemetry.menuBarTitle, "⚡️ 80%")
    }

    public func testBypassStateAndFormatting() throws {
        let bypassed = BatteryTelemetry(
            percentage: 80,
            isCharging: false,
            isPluggedIn: true,
            chargingState: .bypassed,
            isBypassed: true
        )

        XCTAssertEqual(bypassed.chargingState, .bypassed)
        XCTAssertTrue(bypassed.isBypassed)
        XCTAssertEqual(bypassed.menuBarTitle, "⚡️ 80% [AC]")
        XCTAssertEqual(bypassed.menuBarSymbol, "bolt.shield.fill")
        XCTAssertEqual(bypassed.formattedRemainingTime, "AC Power (Bypass Active)")

        // Discharging on battery
        let discharging = BatteryTelemetry(
            percentage: 65,
            isCharging: false,
            isPluggedIn: false,
            timeRemainingMinutes: 195,
            chargingState: .discharging,
            isBypassed: false
        )
        XCTAssertEqual(discharging.menuBarTitle, "65%")
        XCTAssertEqual(discharging.formattedRemainingTime, "3h 15m remaining")
        XCTAssertEqual(discharging.menuBarSymbol, "battery.50")
    }

    public func testSMCFourCCEncoding() throws {
        let keyStr = "B0CT"
        let code = SMCService.fourCharCode(keyStr)
        let decoded = SMCService.codeToString(code)
        XCTAssertEqual(decoded, keyStr)

        let bcmStr = "B0CM"
        let bcmCode = SMCService.fourCharCode(bcmStr)
        XCTAssertEqual(SMCService.codeToString(bcmCode), bcmStr)
    }

    public func testChargeLimiterHysteresisLogic() throws {
        let limiter = ChargeLimiter(
            isLimiterEnabled: true,
            chargeLimit: 80,
            hysteresis: 2
        )

        // 1. Below limit (75% and charging on AC) -> Bypass must NOT be active
        let t1 = BatteryTelemetry(
            percentage: 75,
            isCharging: true,
            isPluggedIn: true,
            chargingState: .charging,
            isBypassed: false
        )
        limiter.evaluateCurrentState(telemetry: t1)
        XCTAssertFalse(limiter.isAdapterBypassActive)

        // 2. Reached limit (80% and on AC) -> Bypass MUST ENGAGE
        let t2 = BatteryTelemetry(
            percentage: 80,
            isCharging: true,
            isPluggedIn: true,
            chargingState: .charging,
            isBypassed: false
        )
        limiter.evaluateCurrentState(telemetry: t2)
        XCTAssertTrue(limiter.isAdapterBypassActive)

        // 3. Fluctuation within hysteresis (79% on AC) -> Bypass must REMAIN ACTIVE
        let t3 = BatteryTelemetry(
            percentage: 79,
            isCharging: false,
            isPluggedIn: true,
            chargingState: .bypassed,
            isBypassed: true
        )
        limiter.evaluateCurrentState(telemetry: t3)
        XCTAssertTrue(limiter.isAdapterBypassActive)

        // 4. Dips below hysteresis threshold (78% <= 80 - 2) -> Bypass must DISENGAGE to resume charging
        let t4 = BatteryTelemetry(
            percentage: 78,
            isCharging: false,
            isPluggedIn: true,
            chargingState: .bypassed,
            isBypassed: true
        )
        limiter.evaluateCurrentState(telemetry: t4)
        XCTAssertFalse(limiter.isAdapterBypassActive)

        // 5. Unplugged from AC -> Bypass must be disengaged
        let t5 = BatteryTelemetry(
            percentage: 85,
            isCharging: false,
            isPluggedIn: false,
            chargingState: .discharging,
            isBypassed: false
        )
        limiter.evaluateCurrentState(telemetry: t5)
        XCTAssertFalse(limiter.isAdapterBypassActive)
    }

    public func testPowerSettingsPresets() throws {
        let presets = PowerSettings.availablePresets
        XCTAssertTrue(presets.contains(70))
        XCTAssertTrue(presets.contains(80))
        XCTAssertTrue(presets.contains(100))
        XCTAssertEqual(PowerSettings.default.chargeLimit, 80)
        XCTAssertTrue(PowerSettings.default.isLimiterEnabled)
    }

    public func testThermalCutoutGuard() throws {
        let limiter = ChargeLimiter(
            isLimiterEnabled: true,
            chargeLimit: 80,
            hysteresis: 3
        )

        // Normal temperature (32.0°C) below charge limit -> charging normally, bypass inactive
        let normalTelemetry = BatteryTelemetry(
            percentage: 60,
            isCharging: true,
            isPluggedIn: true,
            temperature: 32.0,
            chargingState: .charging,
            isBypassed: false
        )
        limiter.evaluateCurrentState(telemetry: normalTelemetry)
        XCTAssertFalse(limiter.isAdapterBypassActive)

        // Thermal surge (41.5°C > 40.0°C) -> Cutout must immediately engage bypass to stop charging
        let hotTelemetry = BatteryTelemetry(
            percentage: 60,
            isCharging: true,
            isPluggedIn: true,
            temperature: 41.5,
            chargingState: .charging,
            isBypassed: false
        )
        limiter.evaluateCurrentState(telemetry: hotTelemetry)
        XCTAssertTrue(limiter.isAdapterBypassActive, "Thermal cutout guard must engage bypass when temperature > 40.0°C")
    }

    public func testSMCHardwareGenerationMatrix() throws {
        let m2Key = SMCService.fourCharCode("CHTE")
        XCTAssertEqual(SMCService.codeToString(m2Key), "CHTE")

        let m1Key = SMCService.fourCharCode("CH0B")
        XCTAssertEqual(SMCService.codeToString(m1Key), "CH0B")

        let intelKey = SMCService.fourCharCode("BCLM")
        XCTAssertEqual(SMCService.codeToString(intelKey), "BCLM")

        let magSafeKey = SMCService.fourCharCode("ACLC")
        XCTAssertEqual(SMCService.codeToString(magSafeKey), "ACLC")
    }

    public func testActuatorCalledOnlyOnChangeAndRetriedOnFailure() throws {
        var calls: [Bool] = []
        var accept = false
        let limiter = ChargeLimiter(isLimiterEnabled: true, chargeLimit: 80, hysteresis: 3) { inhibit, _ in
            calls.append(inhibit)
            return accept
        }
        let atLimit = BatteryTelemetry(percentage: 80, isCharging: true, isPluggedIn: true, chargingState: .charging, isBypassed: false)

        // Write refused (not root): state must not flip, so the next event retries.
        limiter.evaluateCurrentState(telemetry: atLimit)
        XCTAssertFalse(limiter.isAdapterBypassActive)
        accept = true
        limiter.evaluateCurrentState(telemetry: atLimit)
        XCTAssertTrue(limiter.isAdapterBypassActive)
        // Same decision again: no extra hardware write.
        limiter.evaluateCurrentState(telemetry: atLimit)
        XCTAssertEqual(calls, [true, true])
        // Reassert (after wake) writes even without a change.
        limiter.evaluateCurrentState(telemetry: atLimit, reassert: true)
        XCTAssertEqual(calls, [true, true, true])
    }

    public func testBelowLimitNeverPausesCharging() throws {
        let limiter = ChargeLimiter(isLimiterEnabled: true, chargeLimit: 80, hysteresis: 3)
        let low = BatteryTelemetry(percentage: 30, isCharging: true, isPluggedIn: true, chargingState: .charging, isBypassed: false)
        limiter.evaluateCurrentState(telemetry: low, reassert: true)
        XCTAssertFalse(limiter.isAdapterBypassActive, "A limit of 80% must not stop charging at 30%")
    }

    public func testThermalPauseResumesWhenCool() throws {
        let limiter = ChargeLimiter(isLimiterEnabled: true, chargeLimit: 80, hysteresis: 3)
        func t(_ temp: Double) -> BatteryTelemetry {
            BatteryTelemetry(percentage: 60, isCharging: true, isPluggedIn: true, temperature: temp, chargingState: .charging, isBypassed: false)
        }
        limiter.evaluateCurrentState(telemetry: t(41))
        XCTAssertTrue(limiter.isAdapterBypassActive)
        limiter.evaluateCurrentState(telemetry: t(38.5))
        XCTAssertTrue(limiter.isAdapterBypassActive, "Stays paused until it cools below the resume point")
        limiter.evaluateCurrentState(telemetry: t(36))
        XCTAssertFalse(limiter.isAdapterBypassActive)
    }

    public func testChargeLimitConfigRoundTripAndClamping() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fluxbar-config-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try ChargeLimitConfig(isEnabled: true, limit: 85, hysteresis: 4).save(to: url)
        XCTAssertEqual(ChargeLimitConfig.load(from: url), ChargeLimitConfig(isEnabled: true, limit: 85, hysteresis: 4))

        try Data(#"{"isEnabled":true,"limit":12,"hysteresis":99}"#.utf8).write(to: url)
        let clamped = ChargeLimitConfig.load(from: url)
        XCTAssertEqual(clamped?.limit, 50)
        XCTAssertEqual(clamped?.hysteresis, 10)
    }

    public func testNativeLimitRoundsToSupportedValues() throws {
        let limits = [80, 85, 90, 95, 100]
        XCTAssertEqual(NativeChargeLimit.nearestSupported(50, in: limits), 80)
        XCTAssertEqual(NativeChargeLimit.nearestSupported(77, in: limits), 80)
        XCTAssertEqual(NativeChargeLimit.nearestSupported(82, in: limits), 80)
        XCTAssertEqual(NativeChargeLimit.nearestSupported(83, in: limits), 85)
        XCTAssertEqual(NativeChargeLimit.nearestSupported(90, in: limits), 90)
        XCTAssertEqual(NativeChargeLimit.nearestSupported(100, in: limits), 100)
        XCTAssertEqual(ChargeLimitMethod.macOS.minimumLimit, 80)
        XCTAssertEqual(ChargeLimitMethod.helper.minimumLimit, 50)
    }
}
