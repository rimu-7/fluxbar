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
}
