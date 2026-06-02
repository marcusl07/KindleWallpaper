import GRDB

enum DatabaseMigrations {
    private static let migrator: DatabaseMigrator = {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("createInitialSchema") { database in
            try database.execute(sql: DatabaseSchema.createBooksTableSQL)
            try database.execute(sql: DatabaseSchema.createHighlightsTableSQL)
            try DatabaseSchema.createHighlightsIndexes(in: database)
            try database.execute(sql: DatabaseSchema.createHighlightTombstonesTableSQL)
        }

        migrator.registerMigration("addHighlightsIsEnabled") { database in
            guard try !tableColumnNames(in: "highlights", database: database).contains("isEnabled") else { return }
            try database.execute(sql: """
            ALTER TABLE highlights
            ADD COLUMN isEnabled INTEGER NOT NULL DEFAULT 1
            """)
        }

        migrator.registerMigration("makeHighlightsBookIDNullable") { database in
            let columnInfoRows = try Row.fetchAll(database, sql: "PRAGMA table_info(highlights)")
            guard let bookIDColumn = columnInfoRows.first(where: { ($0["name"] as String?) == "bookId" }) else { return }
            let isBookIDNotNull: Int = bookIDColumn["notnull"]
            guard isBookIDNotNull != 0 else { return }

            try database.execute(sql: """
            CREATE TABLE highlights_migrated (
                id          TEXT PRIMARY KEY,
                bookId      TEXT,
                quoteText   TEXT NOT NULL,
                bookTitle   TEXT NOT NULL,
                author      TEXT NOT NULL,
                location    TEXT,
                dateAdded   TEXT,
                lastShownAt TEXT,
                isEnabled   INTEGER NOT NULL DEFAULT 1,
                dedupeKey   TEXT NOT NULL UNIQUE
            );
            """)
            try database.execute(sql: """
            INSERT INTO highlights_migrated (
                id,
                bookId,
                quoteText,
                bookTitle,
                author,
                location,
                dateAdded,
                lastShownAt,
                isEnabled,
                dedupeKey
            )
            SELECT
                id,
                bookId,
                quoteText,
                bookTitle,
                author,
                location,
                dateAdded,
                lastShownAt,
                isEnabled,
                dedupeKey
            FROM highlights
            """)
            try database.execute(sql: "DROP TABLE highlights")
            try database.execute(sql: "ALTER TABLE highlights_migrated RENAME TO highlights")
            try DatabaseSchema.createHighlightsIndexes(in: database)
        }

        migrator.registerMigration("createHighlightTombstones") { database in
            try database.execute(sql: DatabaseSchema.createHighlightTombstonesTableSQL)
        }

        migrator.registerMigration("addHighlightSortIndexes") { database in
            try database.execute(sql: DatabaseSchema.createHighlightsBookTitleIndexSQL)
            try database.execute(sql: DatabaseSchema.createHighlightsAuthorIndexSQL)
            try database.execute(sql: DatabaseSchema.createHighlightsDateAddedIndexSQL)
        }

        migrator.registerMigration("addHighlightPagingIndexes") { database in
            try DatabaseSchema.createHighlightsPageIndexes(in: database)
        }

        migrator.registerMigration("addHighlightMostRecentNonNullSortIndex") { database in
            try database.execute(sql: DatabaseSchema.createHighlightsMostRecentNonNullSortIndexSQL)
        }

        migrator.registerMigration("addHighlightsFTS") { database in
            try database.execute(sql: DatabaseSchema.createHighlightsFTSTableSQL)
            try database.execute(sql: DatabaseSchema.populateHighlightsFTSSQL)
            try database.execute(sql: DatabaseSchema.createHighlightsFTSInsertTriggerSQL)
            try database.execute(sql: DatabaseSchema.createHighlightsFTSDeleteTriggerSQL)
            try database.execute(sql: DatabaseSchema.createHighlightsFTSUpdateTriggerSQL)
        }

        return migrator
    }()

    static func migrate(_ databaseQueue: DatabaseQueue) throws {
        try migrator.migrate(databaseQueue)
    }

    private static func tableColumnNames(in tableName: String, database: Database) throws -> Set<String> {
        let rows = try Row.fetchAll(database, sql: "PRAGMA table_info(\(tableName))")
        return Set(rows.compactMap { row in row["name"] as String? })
    }
}
