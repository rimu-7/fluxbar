import Foundation
import GRDB

public enum Migrations {
    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial_schema") { db in
            // 1. app_settings table
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS app_settings (
                    id INTEGER PRIMARY KEY CHECK (id = 1),
                    maxHistory INTEGER NOT NULL DEFAULT 1000,
                    retentionDays INTEGER NOT NULL DEFAULT 0,
                    isPaused BOOLEAN NOT NULL DEFAULT 0,
                    ignoreConcealed BOOLEAN NOT NULL DEFAULT 1
                );
                INSERT OR IGNORE INTO app_settings (id, maxHistory, retentionDays, isPaused, ignoreConcealed)
                VALUES (1, 1000, 0, 0, 1);
            """)

            // 2. clip_items table
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS clip_items (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    content TEXT NOT NULL,
                    contentHash TEXT NOT NULL UNIQUE,
                    charCount INTEGER NOT NULL,
                    lineCount INTEGER NOT NULL,
                    sourceAppBundleId TEXT,
                    sourceAppName TEXT,
                    copyCount INTEGER NOT NULL DEFAULT 1,
                    isPinned BOOLEAN NOT NULL DEFAULT 0,
                    formatType TEXT NOT NULL DEFAULT 'text',
                    rtfData BLOB,
                    htmlContent TEXT,
                    fileURL TEXT,
                    createdAt DATETIME NOT NULL,
                    updatedAt DATETIME NOT NULL
                );
                CREATE UNIQUE INDEX IF NOT EXISTS idx_clip_items_contentHash ON clip_items (contentHash);
                CREATE INDEX IF NOT EXISTS idx_clip_items_pinned_updated ON clip_items (isPinned DESC, updatedAt DESC);
            """)

            // 3. SQLite FTS5 virtual table indexing content and sourceAppName
            try db.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS clip_items_fts USING fts5(
                    content,
                    sourceAppName,
                    content='clip_items',
                    content_rowid='id'
                );
            """)

            // 4. Triggers to keep FTS5 synchronized with clip_items
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS clip_items_ai AFTER INSERT ON clip_items BEGIN
                    INSERT INTO clip_items_fts(rowid, content, sourceAppName)
                    VALUES (new.id, new.content, new.sourceAppName);
                END;

                CREATE TRIGGER IF NOT EXISTS clip_items_ad AFTER DELETE ON clip_items BEGIN
                    INSERT INTO clip_items_fts(clip_items_fts, rowid, content, sourceAppName)
                    VALUES('delete', old.id, old.content, old.sourceAppName);
                END;

                CREATE TRIGGER IF NOT EXISTS clip_items_au AFTER UPDATE OF content, sourceAppName ON clip_items BEGIN
                    INSERT INTO clip_items_fts(clip_items_fts, rowid, content, sourceAppName)
                    VALUES('delete', old.id, old.content, old.sourceAppName);
                    INSERT INTO clip_items_fts(rowid, content, sourceAppName)
                    VALUES (new.id, new.content, new.sourceAppName);
                END;
            """)

            // 5. Automatic history pruning trigger
            // Enforces capacity and retention age; pinned clips are NEVER pruned.
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS prune_unpinned_history
                AFTER INSERT ON clip_items
                BEGIN
                    DELETE FROM clip_items
                    WHERE isPinned = 0
                      AND (SELECT maxHistory FROM app_settings WHERE id = 1) > 0
                      AND id NOT IN (
                          SELECT id FROM clip_items
                          WHERE isPinned = 0
                          ORDER BY updatedAt DESC
                          LIMIT (SELECT maxHistory FROM app_settings WHERE id = 1)
                      );

                    DELETE FROM clip_items
                    WHERE isPinned = 0
                      AND (SELECT retentionDays FROM app_settings WHERE id = 1) > 0
                      AND updatedAt < datetime('now', '-' || (SELECT retentionDays FROM app_settings WHERE id = 1) || ' days');
                END;
            """)
        }

        migrator.registerMigration("v2_optimize_triggers_and_storage") { db in
            // Recreate clip_items_au so updates to copyCount, updatedAt, isPinned do not trigger FTS5 churn
            try db.execute(sql: """
                DROP TRIGGER IF EXISTS clip_items_au;
                CREATE TRIGGER IF NOT EXISTS clip_items_au AFTER UPDATE OF content, sourceAppName ON clip_items BEGIN
                    INSERT INTO clip_items_fts(clip_items_fts, rowid, content, sourceAppName)
                    VALUES('delete', old.id, old.content, old.sourceAppName);
                    INSERT INTO clip_items_fts(rowid, content, sourceAppName)
                    VALUES (new.id, new.content, new.sourceAppName);
                END;
                PRAGMA wal_autocheckpoint = 25;
                PRAGMA journal_size_limit = 65536;
            """)
        }

        migrator.registerMigration("v3_rich_formats") { db in
            // Check and add rich format columns if migrating from an older DB
            let columns = try db.columns(in: "clip_items")
            let names = Set(columns.map(\.name))
            if !names.contains("formatType") {
                try db.execute(sql: "ALTER TABLE clip_items ADD COLUMN formatType TEXT NOT NULL DEFAULT 'text';")
            }
            if !names.contains("rtfData") {
                try db.execute(sql: "ALTER TABLE clip_items ADD COLUMN rtfData BLOB;")
            }
            if !names.contains("htmlContent") {
                try db.execute(sql: "ALTER TABLE clip_items ADD COLUMN htmlContent TEXT;")
            }
            if !names.contains("fileURL") {
                try db.execute(sql: "ALTER TABLE clip_items ADD COLUMN fileURL TEXT;")
            }
        }

        migrator.registerMigration("v4_retention_and_storage") { db in
            // 1. Add retentionDays column to app_settings if not present
            let settingsCols = try db.columns(in: "app_settings")
            let colNames = Set(settingsCols.map(\.name))
            if !colNames.contains("retentionDays") {
                try db.execute(sql: "ALTER TABLE app_settings ADD COLUMN retentionDays INTEGER NOT NULL DEFAULT 0;")
            }

            // 2. Re-create prune trigger to support retentionDays and maxHistory (0 = unlimited)
            try db.execute(sql: "DROP TRIGGER IF EXISTS prune_unpinned_history;")
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS prune_unpinned_history
                AFTER INSERT ON clip_items
                BEGIN
                    DELETE FROM clip_items
                    WHERE isPinned = 0
                      AND (SELECT maxHistory FROM app_settings WHERE id = 1) > 0
                      AND id NOT IN (
                          SELECT id FROM clip_items
                          WHERE isPinned = 0
                          ORDER BY updatedAt DESC
                          LIMIT (SELECT maxHistory FROM app_settings WHERE id = 1)
                      );

                    DELETE FROM clip_items
                    WHERE isPinned = 0
                      AND (SELECT retentionDays FROM app_settings WHERE id = 1) > 0
                      AND updatedAt < datetime('now', '-' || (SELECT retentionDays FROM app_settings WHERE id = 1) || ' days');
                END;
            """)
        }

        return migrator
    }
}
