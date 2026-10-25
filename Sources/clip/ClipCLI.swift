import Foundation
import ArgumentParser
import ClipCore

@main
struct ClipCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clip",
        abstract: "ClipSuite fast terminal clipboard manager",
        version: "1.0.0",
        subcommands: [
            ListCommand.self,
            CopyCommand.self,
            AddCommand.self,
            PinCommand.self,
            DeleteCommand.self,
            ClearCommand.self,
            StatsCommand.self
        ],
        defaultSubcommand: ListCommand.self
    )
}

// MARK: - List Command

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List recent clips with optional search and filtering"
    )

    @Option(name: .shortAndLong, help: "Full-text search query (FTS5)")
    var search: String?

    @Option(name: .shortAndLong, help: "Maximum number of clips to return")
    var limit: Int = 20

    @Flag(name: .shortAndLong, help: "Show only pinned clips")
    var pinned: Bool = false

    @Flag(name: .long, help: "Output as raw JSON for piping to jq/fzf")
    var json: Bool = false

    func run() throws {
        let db = DatabaseManager.shared
        let query = search ?? ""
        let clips = try db.queryClips(searchQuery: query, limit: limit, pinnedOnly: pinned)

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(clips)
            if let output = String(data: data, encoding: .utf8) {
                print(output)
            }
            return
        }

        if clips.isEmpty {
            print("No clips found.")
            return
        }

        func pad(_ s: String, _ len: Int) -> String {
            if s.count >= len {
                return String(s.prefix(len))
            }
            return s + String(repeating: " ", count: len - s.count)
        }

        // Terminal table output
        print("\(pad("ID", 6)) \(pad("PIN", 4)) \(pad("COPIES", 7)) \(pad("TIME", 10)) \(pad("SOURCE", 14)) CONTENT PREVIEW")
        print(String(repeating: "-", count: 85))

        for (idx, clip) in clips.enumerated() {
            let pinMark = clip.isPinned ? "📌" : "  "
            let idStr = clip.id != nil ? "#\(clip.id!)" : "#\(idx + 1)"
            let copyStr = "\(clip.copyCount)x"
            let timeStr = clip.relativeTimeText
            let appStr = String((clip.sourceAppName ?? "Unknown").prefix(14))
            let preview = String(clip.previewText.replacingOccurrences(of: "\n", with: " ⏎ ").prefix(40))

            print("\(pad(idStr, 6)) \(pad(pinMark, 4)) \(pad(copyStr, 7)) \(pad(timeStr, 10)) \(pad(appStr, 14)) \(preview)")
        }
    }
}

// MARK: - Target Resolution Helper

func resolveClipTarget(_ target: String, idOnly: Bool, db: DatabaseManager) throws -> ClipItem {
    let clean = target.hasPrefix("#") ? String(target.dropFirst()) : target
    guard let num = Int64(clean) else {
        throw ValidationError("Target '\(target)' must be a valid numeric ID (e.g. 12 or #12) or 1-based index.")
    }
    let clips = try db.queryClips(searchQuery: "", limit: 1000)
    if idOnly {
        if let match = clips.first(where: { $0.id == num }) {
            return match
        }
    } else {
        // First check exact ID match
        if let match = clips.first(where: { $0.id == num }) {
            return match
        }
        // Then check 1-based index in the current list
        if num >= 1 && Int(num) <= clips.count {
            return clips[Int(num) - 1]
        }
    }
    throw ValidationError("Clip '\(target)' not found in database or list.")
}

// MARK: - Copy Command

struct CopyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "copy",
        abstract: "Copy a clip directly to NSPasteboard by index or ID"
    )

    @Argument(help: "Target clip ID or 1-based index from list")
    var target: String

    @Flag(name: .long, help: "Treat argument strictly as database ID")
    var id: Bool = false

    func run() throws {
        let db = DatabaseManager.shared
        let clip = try resolveClipTarget(target, idOnly: id, db: db)

        MainActor.assumeIsolated {
            PasteboardService.shared.copyToPasteboard(item: clip)
        }

        print("Copied clip #\(clip.id ?? 0) to clipboard (\(clip.charCount) characters).")
    }
}

// MARK: - Add Command

struct AddCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a new clip to SQLite and copy to clipboard (accepts argument or stdin)"
    )

    @Argument(help: "Text content to save (optional; reads from stdin if omitted)")
    var text: [String] = []

    func run() throws {
        var content: String

        if !text.isEmpty {
            content = text.joined(separator: " ")
        } else {
            // Read from standard input
            let inputData = FileHandle.standardInput.readDataToEndOfFile()
            guard let stdinString = String(data: inputData, encoding: .utf8),
                  !stdinString.isEmpty else {
                throw ValidationError("No input provided. Provide text as an argument or pipe via stdin.")
            }
            content = stdinString
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw ValidationError("Cannot add empty content.")
        }

        let db = DatabaseManager.shared
        let item = try db.recordClip(content: content, sourceAppName: "Terminal (CLI)")

        MainActor.assumeIsolated {
            PasteboardService.shared.copyToPasteboard(item: item)
        }

        print("Saved clip #\(item.id ?? 0) (\(item.charCount) chars, \(item.lineCount) lines).")
    }
}

// MARK: - Pin Command

struct PinCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pin",
        abstract: "Toggle pinned status of a clip by ID or 1-based index"
    )

    @Argument(help: "Clip ID (e.g. 12 or #12) or 1-based list index (e.g. 1)")
    var target: String

    @Flag(name: .long, help: "Treat argument strictly as database ID")
    var id: Bool = false

    func run() throws {
        let db = DatabaseManager.shared
        let clip = try resolveClipTarget(target, idOnly: id, db: db)
        guard let clipId = clip.id else {
            throw ValidationError("Clip does not have a valid ID.")
        }
        let toggled = try db.togglePin(id: clipId)
        if toggled {
            let newStatus = !clip.isPinned
            print("Toggled pin status for clip #\(clipId) (now \(newStatus ? "📌 pinned" : "unpinned")).")
        } else {
            print("Error: Could not toggle pin for clip #\(clipId).")
        }
    }
}

// MARK: - Delete Command

struct DeleteCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a clip by ID or 1-based index"
    )

    @Argument(help: "Clip ID (e.g. 12 or #12) or 1-based list index (e.g. 1)")
    var target: String

    @Flag(name: .long, help: "Treat argument strictly as database ID")
    var id: Bool = false

    func run() throws {
        let db = DatabaseManager.shared
        let clip = try resolveClipTarget(target, idOnly: id, db: db)
        guard let clipId = clip.id else {
            throw ValidationError("Clip does not have a valid ID.")
        }
        let deleted = try db.deleteClip(id: clipId)
        if deleted {
            print("Deleted clip #\(clipId).")
        } else {
            print("Error: Could not delete clip #\(clipId).")
        }
    }
}

// MARK: - Clear Command

struct ClearCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clear",
        abstract: "Clear clips from history"
    )

    @Flag(name: .long, help: "Delete ALL clips including pinned items (fresh start)")
    var all: Bool = false

    @Flag(name: .shortAndLong, help: "Bypass confirmation prompt")
    var force: Bool = false

    func run() throws {
        let db = DatabaseManager.shared
        if !force {
            let promptMsg = all ? "Are you sure you want to delete ALL clips (including pinned)? (y/N): " : "Are you sure you want to delete all unpinned clips? (y/N): "
            print(promptMsg, terminator: "")
            fflush(stdout)
            guard let line = readLine(), line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "y" else {
                print("Aborted.")
                return
            }
        }

        if all {
            try db.deleteAllClips()
            print("All clips (including pinned) permanently deleted.")
        } else {
            try db.clearUnpinned()
            print("All unpinned history cleared.")
        }
    }
}

// MARK: - Stats Command

struct StatsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stats",
        abstract: "Display database size, clip counts, and active settings"
    )

    @Flag(name: .long, help: "Reclaim disk space and truncate WAL log")
    var vacuum: Bool = false

    func run() throws {
        let db = DatabaseManager.shared
        if vacuum {
            try db.optimizeDatabase()
            print("Optimized SQLite database and reclaimed disk storage.")
        }

        let stats = try db.getDatabaseStats()
        let settings = try db.fetchSettings()

        print("=== ClipSuite Database Stats ===")
        print("Database Path:      \(db.dbPath ?? "In-Memory")")
        print("Database Disk Size: \(stats.formattedFileSize)")
        print("Total Clips:        \(stats.totalClips)")
        print("Pinned Clips:       \(stats.pinnedClips)")
        print("Unpinned Clips:     \(stats.totalClips - stats.pinnedClips)")
        print("Max History Limit:  \(settings.maxHistory)")
        print("Recording Status:   \(settings.isPaused ? "PAUSED" : "ACTIVE")")
        print("Ignore Concealed:   \(settings.ignoreConcealed ? "ENABLED" : "DISABLED")")
    }
}
