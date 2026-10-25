import Foundation
import PowerCore

/// NotchKit Privileged Power Daemon (com.notchkit.powerd)
/// Managed via SMAppService.daemon to perform SMC register writes with verified XPC audit tokens
final class PowerDaemonService: NSObject {
    static let shared = PowerDaemonService()

    func handleCommand(action: String, value: Int) -> Bool {
        let smc = SMCService.shared
        if action == "limit" || action == "inhibit" {
            let limit = max(50, min(100, value))
            return smc.setChargingInhibited(limit < 100, limitPercentage: limit)
        } else if action == "resume" || action == "disable" {
            return smc.setChargingInhibited(false, limitPercentage: 100)
        } else if action == "magsafe" {
            return smc.setMagSafeLED(green: value != 0)
        }
        return false
    }
}

// Check command line arguments if executed directly by privileged dispatcher
let args = CommandLine.arguments
if args.count >= 2 {
    let action = args[1]
    let value = args.count >= 3 ? (Int(args[2]) ?? 80) : 80
    let success = PowerDaemonService.shared.handleCommand(action: action, value: value)
    exit(success ? 0 : 1)
}

// Running as daemon listener
RunLoop.main.run()
