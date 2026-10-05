import Foundation

/// Version information for the on-disk index.
public enum SearchIndexVersion {
    /// Schema version (stored in `PRAGMA user_version`). Bump and add a migration when the schema changes.
    public static let schema = 2
    /// Parser/tokenizer version. When it changes, all documents are re-indexed on the next run.
    public static let parser = "1"
}
