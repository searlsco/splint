# Bookshelf — Splint example app

A reading-list app that exercises every Splint type. This folder is a
self-contained Swift package so `swift build` and `swift test` work
from here for CI and local verification:

```sh
cd Example
swift test
```

It is declared as an `.executableTarget` so `BookshelfApp`'s `@main`
compiles and links. To run the iOS app, open `Example/Package.swift`
in Xcode 26.4+ and choose the iOS simulator as the destination — Xcode
will treat the executable target as an iOS app because the `App` scene
is declared.

## What it demonstrates

| Type | Usage |
|------|-------|
| `Resource` | `Book` — immutable value, decoded (in this example: fixtures) |
| `Catalog<Book, BookCriteria>` | Owned by `ContentView` via `@State`, distributed via `.environment()` |
| `Lens<Book>` | `searchLens` (title/author substring) and `genreLens` (by preferred genre) |
| `Job<BookMetadata>` | `@State` in `BookDetailView` — fetches extended metadata on demand |
| `Selection<String>` | Active book id, bound to `List(selection:)` |
| `Setting<Bool>` | `"showCovers"` toggle |
| `Setting<String>` | `"preferredGenre"` filter, persisted across launches |
| `Credential` | (Not surfaced in UI; `BookClient.live` can read an API token) |
| `@Model` + `@Query` | `Favorite` — SwiftData, joined to the `Catalog` by id |

## What it does *not* demonstrate

- Network I/O. `BookClient.mock` returns fixtures after a short sleep.
- Pagination. Out of scope for v0.1.
- Cross-criteria caching. Out of scope for v0.1.
