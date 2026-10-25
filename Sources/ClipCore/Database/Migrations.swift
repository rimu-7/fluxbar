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
                    maxHistory INTEGER NOT NULL DEFAULT 250,
                    isPaused BOOLEAN NOT NULL DEFAULT 0,
                    ignoreConcealed BOOLEAN NOT NULL DEFAULT 1
                );
                INSERT OR IGNORE INTO app_settings (id, maxHistory, isPaused, ignoreConcealed)
                VALUES (1, 250, 0, 1);
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
            // Deletes unpinned rows not in the top (SELECT maxHistory FROM app_settings WHERE id = 1)
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS prune_unpinned_history
                AFTER INSERT ON clip_items
                BEGIN
                    DELETE FROM clip_items
                    WHERE isPinned = 0
                      AND id NOT IN (
                          SELECT id FROM clip_items
                          WHERE isPinned = 0
                          ORDER BY updatedAt DESC
                          LIMIT (SELECT maxHistory FROM app_settings WHERE id = 1)
                      );
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

        return migrator
    }
}
