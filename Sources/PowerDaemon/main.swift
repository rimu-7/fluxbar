import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import PowerCore

// com.fluxbar.powerd — root LaunchDaemon that enforces the battery charge limit.
//
//   com.fluxbar.powerd install [--limit N] [--enabled true|false]   (root) install + start
//   com.fluxbar.powerd uninstall                                     (root) stop, resume charging, remove
//   com.fluxbar.powerd run                                           (launchd) enforce the limit
//
// It sleeps until something changes: power source events, settings file changes, wake from sleep,
// plus a 60 s safety check. No polling loop, ~0% CPU.

let label = PowerHelperManager.label

// IOKit power messages (C macros, not visible to Swift). From <IOKit/IOMessage.h>.
let ioMessageCanSystemSleep: UInt32 = 0xE000_0270
let ioMessageSystemWillSleep: UInt32 = 0xE000_0280
let ioMessageSystemHasPoweredOn: UInt32 = 0xE000_0300
let adminGroupID: gid_t = 80

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("com.fluxbar.powerd: \(message)\n".utf8))
    exit(1)
}

func requireRoot() {
    if geteuid() != 0 { fail("must be run as root (try: sudo flux power install)") }
}

@discardableResult
func launchctl(_ args: [String]) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return -1 }
    p.waitUntilExit()
    return p.terminationStatus
}

func option(_ name: String, in args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

// MARK: - install

func install(arguments: [String]) {
    requireRoot()
    let fm = FileManager.default
    let dest = PowerHelperManager.installedBinaryPath

    // 1. Copy this binary into place (root:wheel 0755) unless we're already running from there.
    let me = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
    if me != dest {
        let tmp = dest + ".new"
        try? fm.createDirectory(atPath: "/Library/PrivilegedHelperTools", withIntermediateDirectories: true)
        try? fm.removeItem(atPath: tmp)
        do { try fm.copyItem(atPath: me, toPath: tmp) } catch { fail("copy failed: \(error.localizedDescription)") }
        chown(tmp, 0, 0)
        chmod(tmp, 0o755)
        if rename(tmp, dest) != 0 { fail("could not move helper into place") }
    }

    // 2. Settings folder: root:admin 0775, so admin users can change the limit without a password.
    let dir = ChargeLimitConfig.directoryURL.path
    try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
    chown(dir, 0, adminGroupID)
    chmod(dir, 0o775)

    var config = ChargeLimitConfig.load() ?? .default
    if let limit = option("--limit", in: arguments).flatMap(Int.init) { config.limit = ChargeLimitConfig.clampLimit(limit) }
    if let enabled = option("--enabled", in: arguments) { config.isEnabled = (enabled == "true" || enabled == "1") }
    do { try config.save() } catch { fail("could not write settings: \(error.localizedDescription)") }
    chown(ChargeLimitConfig.fileURL.path, 0, adminGroupID)
    chmod(ChargeLimitConfig.fileURL.path, 0o664)

    // 3. LaunchDaemon plist.
    let plist: [String: Any] = [
        "Label": label,
        "ProgramArguments": [dest, "run"],
        "RunAtLoad": true,
        "KeepAlive": true,
        "ProcessType": "Background",
        "LowPriorityIO": true,
        "ThrottleInterval": 30
    ]
    do {
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: PowerHelperManager.launchDaemonPlistPath), options: .atomic)
    } catch {
        fail("could not write launchd plist: \(error.localizedDescription)")
    }
    chown(PowerHelperManager.launchDaemonPlistPath, 0, 0)
    chmod(PowerHelperManager.launchDaemonPlistPath, 0o644)

    // 4. Remove leftovers from older versions.
    for path in PowerHelperManager.legacyPaths { try? fm.removeItem(atPath: path) }
    launchctl(["bootout", "system/com.notchkit.powerd"])

    // 5. (Re)start.
    launchctl(["bootout", "system/\(label)"])
    let status = launchctl(["bootstrap", "system", PowerHelperManager.launchDaemonPlistPath])
    if status != 0 && launchctl(["kickstart", "-k", "system/\(label)"]) != 0 {
        fail("launchctl bootstrap failed (\(status))")
    }
    print("Battery helper installed. Limit: \(config.isEnabled ? "\(config.limit)%" : "off")")
}

// MARK: - uninstall

func uninstall() {
    requireRoot()
    let fm = FileManager.default
    launchctl(["bootout", "system/\(label)"])
    SMCService.shared.setChargingInhibited(false, limitPercentage: 100)
    try? fm.removeItem(atPath: PowerHelperManager.launchDaemonPlistPath)
    try? fm.removeItem(at: ChargeLimitConfig.directoryURL)
    for path in PowerHelperManager.legacyPaths { try? fm.removeItem(atPath: path) }
    try? fm.removeItem(atPath: PowerHelperManager.installedBinaryPath)
    print("Battery helper removed. Normal charging restored.")
}

// MARK: - run

final class Daemon {
    let smc = SMCService.shared
    lazy var limiter = ChargeLimiter(config: ChargeLimitConfig.load() ?? .default) { [smc] inhibit, limit in
        smc.setChargingInhibited(inhibit, limitPercentage: limit)
    }
    var lastStatus: PowerDaemonStatus?
    var sources: [Any] = []
    var rootPort: io_connect_t = 0
    var notifier: io_object_t = 0

    func evaluate(reassert: Bool) {
        let telemetry = BatteryMonitor.fetchTelemetry(deep: false)
        limiter.evaluateCurrentState(telemetry: telemetry, reassert: reassert)
        writeStatus()
    }

    func reloadConfig() {
        let config = ChargeLimitConfig.load() ?? .default
        limiter.configure(config)
        evaluate(reassert: true)
    }

    func writeStatus() {
        let status = PowerDaemonStatus(
            isChargingInhibited: limiter.isAdapterBypassActive,
            reason: limiter.lastReason,
            hardware: smc.detectedHardwareGeneration.rawValue,
            smcWritable: smc.detectedHardwareGeneration != .unsupported
        )
        // Only touch the disk when something visible changed.
        if let last = lastStatus,
           last.isChargingInhibited == status.isChargingInhibited,
           last.reason == status.reason { return }
        lastStatus = status
        status.save()
    }

    func start() {
        requireRoot()
        try? FileManager.default.createDirectory(at: ChargeLimitConfig.directoryURL, withIntermediateDirectories: true)

        // Power source changes (plug/unplug, percentage ticks).
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<Daemon>.fromOpaque(ctx).takeUnretainedValue().evaluate(reassert: false)
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }

        // Settings changes: watch the folder (atomic saves replace the file).
        let fd = open(ChargeLimitConfig.directoryURL.path, O_EVTONLY)
        if fd >= 0 {
            let watcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
            watcher.setEventHandler { [weak self] in self?.reloadConfig() }
            watcher.setCancelHandler { close(fd) }
            watcher.resume()
            sources.append(watcher)
        }

        // Sleep / wake: re-assert after wake, the SMC can reset charge control while asleep.
        var notifyPort: IONotificationPortRef?
        rootPort = IORegisterForSystemPower(ctx, &notifyPort, { ctx, _, messageType, messageArgument in
            guard let ctx else { return }
            let daemon = Unmanaged<Daemon>.fromOpaque(ctx).takeUnretainedValue()
            switch messageType {
            case ioMessageCanSystemSleep, ioMessageSystemWillSleep:
                IOAllowPowerChange(daemon.rootPort, Int(bitPattern: messageArgument))
            case ioMessageSystemHasPoweredOn:
                daemon.evaluate(reassert: true)
            default:
                break
            }
        }, &notifier)
        if let notifyPort {
            CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue(), .defaultMode)
        }

        // Safety net in case a notification is missed.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 60, repeating: 60, leeway: .seconds(15))
        timer.setEventHandler { [weak self] in self?.evaluate(reassert: false) }
        timer.resume()
        sources.append(timer)

        // On stop (uninstall, shutdown): never leave charging paused.
        signal(SIGTERM, SIG_IGN)
        let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        term.setEventHandler { [weak self] in
            self?.smc.setChargingInhibited(false, limitPercentage: 100)
            exit(0)
        }
        term.resume()
        sources.append(term)

        evaluate(reassert: true)
        CFRunLoopRun()
    }
}

// MARK: - Entry

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "install":
    install(arguments: args)
case "uninstall":
    uninstall()
case "run":
    Daemon().start()
default:
    print("""
    usage: com.fluxbar.powerd install [--limit 50-100] [--enabled true|false]
           com.fluxbar.powerd uninstall
           com.fluxbar.powerd run
    Tip: use 'flux power install' instead of calling this directly.
    """)
    exit(args.count > 1 ? 1 : 0)
}
