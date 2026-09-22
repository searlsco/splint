# Splint

[![Certified Shovelware](https://justin.searls.co/img/shovelware.svg)](https://justin.searls.co/shovelware/)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fsearlsco%2Fsplint%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/searlsco/splint)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fsearlsco%2Fsplint%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/searlsco/splint)

Learn Splint interactively: [Naming the Shapes](https://artifact.land/@scott/naming-the-shapes-1) on artifact.land.

Named data types for SwiftUI apps. Splint is a small library that gives
every data shape in your app a name — so that an agent (or anyone else)
reaching for a value reaches for the right kind of value. It is
*corrective, not prescriptive*: it immobilizes the data skeleton so it
heals correctly.

Agents building SwiftUI apps consistently produce a god-object
`@Observable` class with 15+ properties that every view observes, causing
cascading re-renders across the view hierarchy. The root cause is not
data *flow* — it's data *modeling*. Splint names the types.

## Install

```swift
dependencies: [
    .package(url: "https://github.com/searlsco/splint", from: "0.1.0")
]
```

Then drop the agent rules file into your project:

```sh
mkdir -p .claude/rules
curl -fsSL https://raw.githubusercontent.com/searlsco/splint/main/claude/rules/splint.md \
  -o .claude/rules/splint.md
```

Commit the resulting `.claude/rules/splint.md`. Re-run the `curl` to
pick up rule changes when you bump the Splint package version.

## Quick start

```swift
import Splint

struct Book: Resource {
    let id: String
    let title: String
    let author: String
}

struct BookCriteria: Equatable, Sendable {
    let libraryID: String
}

let catalog = Catalog<Book, BookCriteria> { criteria in
    try await api.fetchBooks(in: criteria.libraryID)
}

// Or seed from a disk cache so the UI renders immediately on cold launch.
// The seed stays visible through the first load() until the fetch lands.
//   Catalog<Book, BookCriteria>(initialItems: cachedBooks) { criteria in … }

catalog.load(BookCriteria(libraryID: "main"))

let favorites = Lens<Book>(source: catalog, filter: { $0.isFavorite })
```

## The type inventory

| Type | What it holds | Observation | Persistence | Mutability |
|------|---------------|-------------|-------------|------------|
| `Resource` | Decoded remote data (channels, programs, episodes) | None — value type | None | Immutable after decode |
| `Catalog` | Ordered collection of Resources loaded by criteria, plus fetch lifecycle | `@Observable` | None (in-memory cache) | Collection mutates on load/refresh |
| `Lens` | Filtered/sorted view over a Catalog | `@Observable` | None | Criteria mutate; data is derived |
| `GroupedLens` | Filtered/sorted view over a Catalog plus cached grouped sections | `@Observable` | None | Criteria mutate; data is derived |
| `Job` | Async operation lifecycle (idle → running → completed/failed) | `@Observable` | None | Phase mutates as work progresses |
| `Selection` | Currently selected item identifier | `@Observable` | None | Mutates on user tap |
| `Setting` | Single typed user preference | `@Observable` | UserDefaults | Mutates, persists automatically |
| `CloudSync` | Mirrors chosen `Setting` keys to iCloud key-value storage | None | iCloud KVS | Uploads when a mirrored Setting mutates |
| `Credential` | Keychain-backed secret | None — read on demand | Keychain | Mutates via explicit save/delete |

**There is no `ViewState` type.** If a value doesn't fit one of the types
above, it's `@State` on the view that owns it.

## Documentation

Guides and API reference live in the DocC catalog, hosted on
[Swift Package Index](https://swiftpackageindex.com/searlsco/splint/documentation/splint).

## License

MIT. See `LICENSE`.
