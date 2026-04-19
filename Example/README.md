# Bookshelf — Splint example app

A reading-list app that exercises every Splint type.

## Running the app

Open `Bookshelf.xcodeproj` in Xcode 26.4+ and pick a destination:

- **iOS Simulator** — any iPhone or iPad sim.
- **My Mac** — runs as a native macOS app.

The scheme signs to run locally (no development team required).

## Running the tests

`Example/` doubles as a Swift package so `swift test` exercises
`BookshelfTests` without opening Xcode. `script/test` at the repo
root runs this suite alongside the library's own tests:

```sh
cd Example
swift test
```

The `.xcodeproj` and the `Package.swift` both reference the same
source files — there's no duplication.

## What it demonstrates

| Type | Usage |
|------|-------|
| `Resource` | `Book` — immutable value, decoded (in this example: fixtures) |
| `Catalog<Book, BookCriteria>` | Owned by `ContentView` via `@State`, distributed via `.environment()` |
| `GroupedLens<Book, String>` | `displayLens` — composite filter (search + preferred genre) with optional grouping by author or genre |
| `Job<BookMetadata>` | `@State` in `BookDetailView` — fetches extended metadata on demand |
| `Selection<String>` | Active book id, bound to `List(selection:)` |
| `Setting<Bool>` | `"showCovers"` toggle |
| `Setting<String>` | `"preferredGenre"` filter, persisted across launches |
| `Credential` | Settings → API: save/clear a device-local token; `BookClient.live` reads it per request |
| `@Model` + `@Query` | `Favorite` — SwiftData, joined to the `Catalog` by id |

## What it does *not* demonstrate

- Network I/O. `BookClient.mock` returns fixtures after a short sleep.
- Pagination. Out of scope for v0.1.
- Cross-criteria caching. Out of scope for v0.1.
