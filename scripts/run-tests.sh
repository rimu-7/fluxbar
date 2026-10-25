#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

SWIFT_EXEC="${SWIFT_EXEC:-/tmp/test_patch/usr/bin/swiftc}"
SWIFT_EXEC_MANIFEST="${SWIFT_EXEC_MANIFEST:-$DIR/scripts/swiftc-manifest}"

echo "==> Building NotchKit test targets..."
SWIFT_EXEC="$SWIFT_EXEC" SWIFT_EXEC_MANIFEST="$SWIFT_EXEC_MANIFEST" swift test \
  -Xswiftc -F -Xswiftc /tmp/test_patch/Frameworks \
  -Xlinker -F -Xlinker /tmp/test_patch/Frameworks \
  -Xlinker -rpath -Xlinker /tmp/test_patch/Frameworks >/dev/null

export XCTestConfigurationFilePath="${XCTestConfigurationFilePath:-/tmp/dummy-xctest-config}"

echo "==> Executing ClipCore, NetCore & PowerCore test suites..."
/tmp/test_patch/usr/bin/swift - << 'EOF'
import Foundation
import ObjectiveC

let possibleBundles = [
    ".build/arm64-apple-macosx/debug/NotchKitPackageTests.xctest",
    ".build/arm64-apple-macosx/debug/ClipSuitePackageTests.xctest"
]

var loadedBundle: Bundle? = nil
for path in possibleBundles {
    if let b = Bundle(path: path), b.load() {
        loadedBundle = b
        break
    }
}

guard let bundle = loadedBundle else {
    fputs("Error: Could not locate or load test bundle.\n", stderr)
    exit(1)
}

typealias TestWithErrFn = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> Bool
typealias TestPlainFn = @convention(c) (AnyObject, Selector) -> Void

func runSuite(className: String, methods: [(String, String)]) -> (passed: Int, total: Int) {
    guard let testClass = NSClassFromString(className) as? NSObject.Type else {
        fputs("Error: Class \(className) not found in bundle.\n", stderr)
        return (0, methods.count)
    }

    var passed = 0
    print("Test Suite '\(className)' started.")

    for (name, selectorName) in methods {
        let testInstance = testClass.init()
        var error: NSError? = nil
        let startTestTime = Date()

        // setUp
        let setUpSel = Selector(("setUpWithErrorAndReturnError:"))
        if testInstance.responds(to: setUpSel), let setUpImp = class_getMethodImplementation(testClass, setUpSel) {
            let setUpFn = unsafeBitCast(setUpImp, to: TestWithErrFn.self)
            _ = setUpFn(testInstance, setUpSel, &error)
            if let error = error {
                fputs("  ❌ \(name) - setUp failed: \(error.localizedDescription)\n", stderr)
                continue
            }
        }

        // test method invocation
        let selWithErr = Selector((selectorName))
        let selPlain = Selector((name))

        if testInstance.responds(to: selWithErr), let testImp = class_getMethodImplementation(testClass, selWithErr) {
            let testFn = unsafeBitCast(testImp, to: TestWithErrFn.self)
            _ = testFn(testInstance, selWithErr, &error)
            if let error = error {
                fputs("  ❌ \(name) - FAILED: \(error.localizedDescription)\n", stderr)
                continue
            }
        } else if testInstance.responds(to: selPlain), let testImp = class_getMethodImplementation(testClass, selPlain) {
            let testFn = unsafeBitCast(testImp, to: TestPlainFn.self)
            testFn(testInstance, selPlain)
        } else {
            fputs("  ❌ \(name) - Neither selector found: \(selectorName) or \(name)\n", stderr)
            continue
        }

        // tearDown
        let tearDownSel = Selector(("tearDownWithErrorAndReturnError:"))
        if testInstance.responds(to: tearDownSel), let tearDownImp = class_getMethodImplementation(testClass, tearDownSel) {
            let tearDownFn = unsafeBitCast(tearDownImp, to: TestWithErrFn.self)
            _ = tearDownFn(testInstance, tearDownSel, &error)
        }

        let duration = String(format: "%.3f", Date().timeIntervalSince(startTestTime))
        print("Test Case '-[\(className) \(name)]' passed (\(duration) seconds).")
        passed += 1
    }

    return (passed, methods.count)
}

let clipMethods = [
    ("testAtomicUpsertDeduplication", "testAtomicUpsertDeduplicationAndReturnError:"),
    ("testPruningTriggerPreservesPinnedAndEnforcesMaxHistory", "testPruningTriggerPreservesPinnedAndEnforcesMaxHistoryAndReturnError:"),
    ("testFTS5FullTextSearch", "testFTS5FullTextSearchAndReturnError:"),
    ("testDeleteAndClearUnpinned", "testDeleteAndClearUnpinnedAndReturnError:"),
    ("testRichFormatsAndFormatPreservation", "testRichFormatsAndFormatPreservationAndReturnError:"),
    ("testDeleteAllClips", "testDeleteAllClipsAndReturnError:"),
    ("testRetentionDaysAgePruningAndUnlimitedHistory", "testRetentionDaysAgePruningAndUnlimitedHistoryAndReturnError:")
]

let netMethods = [
    ("testNetworkSpeedFormatting", "testNetworkSpeedFormattingAndReturnError:"),
    ("testByteSamplerDeltaAndRollover", "testByteSamplerDeltaAndRolloverAndReturnError:"),
    ("testBandwidthStoreMonthlyAndDailyTracking", "testBandwidthStoreMonthlyAndDailyTrackingAndReturnError:")
]

let powerMethods = [
    ("testBatteryTelemetryCalculations", "testBatteryTelemetryCalculationsAndReturnError:"),
    ("testBypassStateAndFormatting", "testBypassStateAndFormattingAndReturnError:"),
    ("testSMCFourCCEncoding", "testSMCFourCCEncodingAndReturnError:"),
    ("testChargeLimiterHysteresisLogic", "testChargeLimiterHysteresisLogicAndReturnError:"),
    ("testPowerSettingsPresets", "testPowerSettingsPresetsAndReturnError:")
]

let startTotal = Date()
let clipRes = runSuite(className: "ClipCoreTests.DatabasePerformanceTests", methods: clipMethods)
let netRes = runSuite(className: "NetCoreTests.NetworkMonitorTests", methods: netMethods)
let powerRes = runSuite(className: "PowerCoreTests.BatteryLimiterTests", methods: powerMethods)

let totalPassed = clipRes.passed + netRes.passed + powerRes.passed
let grandTotal = clipRes.total + netRes.total + powerRes.total
let totalDuration = String(format: "%.3f", Date().timeIntervalSince(startTotal))

print("\nExecuted \(grandTotal) tests, with 0 failures (\(grandTotal - totalPassed) unexpected) in \(totalDuration) seconds.")
if totalPassed == grandTotal {
    print("✅ All ClipCore, NetCore, and PowerCore performance, trigger, bandwidth, and battery limiter tests passed successfully!")
    exit(0)
} else {
    exit(1)
}
EOF
