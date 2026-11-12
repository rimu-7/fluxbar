import Foundation
import Combine
import IOKit.pwr_mgt

/// Keeps the display awake while active, using a `PreventUserIdleDisplaySleep` power assertion.
///
/// The assertion is owned by this process: it is released on `deactivate()`, on app quit
/// (`AppDelegate.applicationWillTerminate`), and by the kernel automatically if FluxBar crashes,
/// so the Mac can never be left stuck awake.
@MainActor
public final class CaffeineManager: ObservableObject {
    public static let shared = CaffeineManager()

    /// Bind to this from SwiftUI. Setting it creates / releases the assertion.
    @Published public var isActive: Bool = false {
        didSet {
            guard isActive != oldValue else { return }
            isActive ? activate() : deactivate()
        }
    }

    /// When the current assertion was taken (nil while inactive).
    @Published public private(set) var activeSince: Date?

    private var assertionID: IOPMAssertionID = IOPMAssertionID(kIOPMNullAssertionID)

    private init() {}

    public func toggle() {
        isActive.toggle()
    }

    private func activate() {
        guard assertionID == IOPMAssertionID(kIOPMNullAssertionID) else { return }

        var newID = IOPMAssertionID(kIOPMNullAssertionID)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "FluxBar Caffeine is keeping the display awake" as CFString,
            &newID
        )

        if result == kIOReturnSuccess {
            assertionID = newID
            activeSince = Date()
        } else {
            print("Caffeine: failed to create power assertion (IOReturn \(result))")
            assertionID = IOPMAssertionID(kIOPMNullAssertionID)
            activeSince = nil
            // Reflect the failure back to the UI without re-entering activate().
            DispatchQueue.main.async { [weak self] in self?.isActive = false }
        }
    }

    private func deactivate() {
        releaseAssertion()
    }

    /// Releases the assertion if one is held. Safe to call any number of times.
    public func releaseAssertion() {
        if assertionID != IOPMAssertionID(kIOPMNullAssertionID) {
            IOPMAssertionRelease(assertionID)
            assertionID = IOPMAssertionID(kIOPMNullAssertionID)
        }
        activeSince = nil
        if isActive { isActive = false }
    }
}
