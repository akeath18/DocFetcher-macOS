# DocFetcher-macOS

A native Swift/SwiftUI rewrite of [DocFetcher](http://docfetcher.sourceforge.net/) for modern macOS: fast
full-text desktop search over your documents, plus document merging and OCR clean-up.

## Features

- **Search** – SQLite FTS5 with BM25 ranking; `AND` / `OR` / `NOT` / `-term`, `"phrases"`, `prefix*`, parentheses,
  field queries (`filename:`, `title:`, `author:`, `content:`), filters (`type:pdf`, `after:2024-01-01`,
  `before:2024-12-31`), fuzzy (typo tolerant) matching, suggestions, history and saved searches, highlighted snippets.
- **Formats** – TXT/MD/CSV/source, HTML, RTF, PDF (PDFKit), DOCX/XLSX/PPTX, ODT/ODS/ODP/ODG, EPUB, SVG,
  legacy DOC/XLS/PPT/CHM (best-effort text extraction), MP3 (ID3) and FLAC tags, image EXIF, and ZIP/TAR/GZ archives
  (entries are searched individually). Corrupted files are recorded as errors and never stop indexing.
- **Indexing** – incremental (only new/changed files are re-parsed, deleted files are removed), persisted on disk,
  background and cancellable, schema versioning with migrations.
- **Merging** – combine documents into one virtual document that keeps its sources and metadata; merge history and undo.
- **OCR** – scanned PDFs/images are detected and recognised with Vision (Tesseract CLI fallback for images);
  stray symbols are cleaned, confidence is scored, and you can toggle between OCR and original text.
- **Export** – CSV, JSON and PDF.

## Layout

```
Sources/DocFetcherCore   Search, indexing, parsers, OCR, merging, export (portable; builds on Linux too)
Sources/App              SwiftUI app (macOS only): views, view models, components
Sources/CSQLite          System SQLite shim used on Linux only
Tests/DocFetcherCoreTests
```

## Build & run

Requires Swift 5.9+ (Xcode 15+) and macOS 13+.

```sh
swift build -c release
swift run DocFetcher        # launches the app
swift test                  # runs the core test suite
```

ZIP-based formats and archives use the system `unzip`, `tar` and `gzip` tools (present on macOS). For the
optional Tesseract fallback install it with `brew install tesseract`.

## Notes

- Index location: `~/Library/Application Support/DocFetcher/index.sqlite`.
- The SQLite layer talks to the system SQLite directly (no third-party packages).
- Spotlight integration is not implemented.

## Contributing

Fork, create a branch, keep changes focused, add tests under `Tests/DocFetcherCoreTests`, and make sure
`swift test` passes. New file formats: implement `DocumentParser` and add it to `ParserRegistry.registerDefaults()`.
