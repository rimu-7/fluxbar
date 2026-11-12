import AppKit
import ClipCore

/// Graphical guidance and a non-invasive packaged-app check used by release CI.
enum AppInstallation {
    static func checkBundle(_ bundle: Bundle = .main) throws {
        guard bundle.bundleURL.pathExtension == "app",
              bundle.bundleIdentifier == FluxBarInfo.bundleIdentifier,
              bundle.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true else {
            throw CheckError.invalidBundle
        }
        for name in ["FluxBar", "flux", "clip", "com.fluxbar.powerd"] {
            let url = bundle.bundleURL.appendingPathComponent("Contents/MacOS/\(name)")
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                throw CheckError.missingComponent(name)
            }
        }
        guard let resources = bundle.resourceURL,
              FileManager.default.fileExists(atPath: resources.appendingPathComponent("GRDB_GRDB.bundle").path) else {
            throw CheckError.missingComponent("database resources")
        }
    }

    /// Running from a mounted disk image or App Translocation cannot support updates reliably.
    /// Explain the normal drag-to-install flow before starting monitors or requesting privileges.
    @MainActor
    static func explainDiskImageIfNeeded() -> Bool {
        let path = Bundle.main.bundleURL.path
        let volume = try? Bundle.main.bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey])
        let onReadOnlyVolume = path.hasPrefix("/Volumes/") && volume?.volumeIsReadOnly == true
        guard onReadOnlyVolume || path.contains("/AppTranslocation/") else { return false }
        let alert = NSAlert()
        alert.messageText = "Move FluxBar to Applications"
        alert.informativeText = "Drag FluxBar from the disk image into Applications, eject the disk image, then open FluxBar from Applications. Battery setup and updates are available inside the app."
        alert.addButton(withTitle: "Open Applications")
        alert.addButton(withTitle: "Quit")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
        }
        NSApp.terminate(nil)
        return true
    }

    enum CheckError: LocalizedError {
        case invalidBundle
        case missingComponent(String)

        var errorDescription: String? {
            switch self {
            case .invalidBundle: return "FluxBar’s app bundle is invalid. Download a fresh DMG from Releases."
            case .missingComponent(let name): return "FluxBar is missing \(name). Replace it with a fresh copy from the DMG."
            }
        }
    }
}
