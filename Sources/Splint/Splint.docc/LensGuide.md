# Lenses over a catalog

A derived, read-only view over a ``Catalog`` — filtering, sorting, or
both — kept in sync automatically.

## Overview

A ``Lens`` watches its source catalog's `items` and recomputes its own
projection when the source changes or when the filter/sort predicates
change. The source's `Criteria` type is erased at init: call sites see
`Lens<Channel>`, not `Lens<Channel, ProviderCriteria>`.

Reach for a lens instead of maintaining a parallel array synced by
hand. Duplicate arrays are one of the bugs ``Lens`` exists to prevent.

## Usage

```swift
let favorites = Lens<Book>(source: catalog, filter: { $0.isFavorite })
```

## Performance

`Lens` recomputes the full projection when the source catalog's items
change — O(n) for the filter pass, plus O(n log n) for the sort
(stdlib introsort) when one is set. Under ~1k items this is
negligible. For larger datasets, consider whether filtering belongs in
the fetch closure (server-side filtering via the catalog's `Criteria`)
rather than in a client-side lens.

## Closures capture once

``Lens`` captures `filter` and `sort` at init. They re-run only on
`updateFilter` / `updateSort` — not when variables they reference
change. Capturing mutable view state at init compiles and looks
correct, and fails silently:

```swift
// ❌ minRating capture goes stale — Lens never sees changes
@State private var minRating = 0
@State private var lens = Lens(source: catalog, filter: { $0.rating >= minRating })

// ✅ Drive updates explicitly
@State private var minRating = 0
@State private var lens = Lens(source: catalog)

var body: some View {
    BookListView(lens: lens)
        .onChange(of: minRating) { _, new in
            lens.updateFilter { $0.rating >= new }
        }
}
```

Same rule as ``Catalog``'s fetch closure: Splint closures capture at
construction; mutable inputs flow through update methods.

## See also

For sectioned `List` / `ForEach { Section }` rendering, use
``GroupedLens`` — it adds a cached `groups` projection on top of the
same filter + sort so you can render groups without recomputing
`Dictionary(grouping:)` on every view body evaluation.

## Topics

### Related

- ``Catalog``
- ``GroupedLens``
- ``Resource``
- <doc:GroupedLensGuide>
- <doc:ObservationBoundaries>
