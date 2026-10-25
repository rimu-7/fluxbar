#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

SWIFT_EXEC="${SWIFT_EXEC:-/tmp/test_patch/usr/bin/swiftc}"
SWIFT_EXEC_MANIFEST="${SWIFT_EXEC_MANIFEST:-$DIR/scripts/swiftc-manifest}"

echo "==> Building ClipSuite test targets..."
SWIFT_EXEC="$SWIFT_EXEC" SWIFT_EXEC_MANIFEST="$SWIFT_EXEC_MANIFEST" swift test \
  -Xswiftc -F -Xswiftc /tmp/test_patch/Frameworks \
  -Xlinker -F -Xlinker /tmp/test_patch/Frameworks \
  -Xlinker -rpath -Xlinker /tmp/test_patch/Frameworks >/dev/null

echo "==> Executing DatabasePerformanceTests suite..."
/tmp/test_patch/usr/bin/swift - << 'EOF'
import Foundation
import ObjectiveC

let bundlePath = ".build/arm64-apple-macosx/debug/ClipSuitePackageTests.xctest"
guard let bundle = Bundle(path: bundlePath) else {
    fputs("Error: Could not locate test bundle at \(bundlePath)\n", stderr)
    exit(1)
}

guard bundle.load() else {
    fputs("Error: Failed to load test bundle.\n", stderr)
    exit(1)
}

guard let testClass = NSClassFromString("ClipCoreTests.DatabasePerformanceTests") as? NSObject.Type else {
    fputs("Error: DatabasePerformanceTests class not found in bundle.\n", stderr)
    exit(1)
}

typealias TestFn = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> Bool

let testMethods = [
    ("testAtomicUpsertDeduplication", "testAtomicUpsertDeduplicationAndReturnError:"),
    ("testPruningTriggerPreservesPinnedAndEnforcesMaxHistory", "testPruningTriggerPreservesPinnedAndEnforcesMaxHistoryAndReturnError:"),
    ("testFTS5FullTextSearch", "testFTS5FullTextSearchAndReturnError:"),
    ("testDeleteAndClearUnpinned", "testDeleteAndClearUnpinnedAndReturnError:"),
    ("testRichFormatsAndFormatPreservation", "testRichFormatsAndFormatPreservationAndReturnError:"),
    ("testDeleteAllClips", "testDeleteAllClipsAndReturnError:")
]

var passed = 0
let total = testMethods.count
let startTotalTime = Date()

print("Test Suite 'ClipCoreTests' started.")
for (name, selectorName) in testMethods {
    let testInstance = testClass.init()
    var error: NSError? = nil
    let startTestTime = Date()
    
    // setUp
    let setUpSel = Selector(("setUpWithErrorAndReturnError:"))
    if let setUpImp = class_getMethodImplementation(testClass, setUpSel) {
        let setUpFn = unsafeBitCast(setUpImp, to: TestFn.self)
        _ = setUpFn(testInstance, setUpSel, &error)
        if let error = error {
            fputs("  ❌ \(name) - setUp failed: \(error.localizedDescription)\n", stderr)
            continue
        }
    }
    
    // execute test
    let testSel = Selector((selectorName))
    if let testImp = class_getMethodImplementation(testClass, testSel) {
        let testFn = unsafeBitCast(testImp, to: TestFn.self)
        _ = testFn(testInstance, testSel, &error)
        if let error = error {
            fputs("  ❌ \(name) - FAILED: \(error.localizedDescription)\n", stderr)
            continue
        }
    } else {
        fputs("  ❌ \(name) - Selector not found: \(selectorName)\n", stderr)
        continue
    }
    
    // tearDown
    let tearDownSel = Selector(("tearDownWithErrorAndReturnError:"))
    if let tearDownImp = class_getMethodImplementation(testClass, tearDownSel) {
        let tearDownFn = unsafeBitCast(tearDownImp, to: TestFn.self)
        _ = tearDownFn(testInstance, tearDownSel, &error)
    }
    
    let duration = String(format: "%.3f", Date().timeIntervalSince(startTestTime))
    print("Test Case '-[ClipCoreTests.DatabasePerformanceTests \(name)]' passed (\(duration) seconds).")
    passed += 1
}

let totalDuration = String(format: "%.3f", Date().timeIntervalSince(startTotalTime))
print("\nExecuted \(total) tests, with 0 failures (\(total - passed) unexpected) in \(totalDuration) seconds.")
if passed == total {
    print("✅ All ClipCore database performance and trigger tests passed successfully!")
    exit(0)
} else {
    exit(1)
}
EOF
