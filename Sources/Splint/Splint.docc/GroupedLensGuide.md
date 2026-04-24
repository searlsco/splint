# Grouped lenses for sectioned lists

A ``GroupedLens`` is a derived, read-only 2-D projection over a
``Catalog``: filter + sort + grouping, kept in sync automatically. Use
it when you render sectioned content — `ForEach { Section }`.

## Overview

``Lens`` gives you a filtered, sorted flat array. ``GroupedLens``
gives you the same `items` *plus* a cached `groups` property shaped as
`[(category: Category, items: [Item])]`, produced by a caller-supplied
`(Item) -> Category` closure. Groups are ordered by `Category`'s
`Comparable` conformance; items within each group preserve the lens's
sort order.

The source catalog's `Criteria` type is erased at init: call sites see
`GroupedLens<Book, String>`, not `GroupedLens<Book, BookCriteria,
String>`.

## Usage

```swift
let lens = GroupedLens<Book, String>(
  source: catalog,
  sort: { $0.title < $1.title },
  categorize: { $0.author })

// In the view:
List {
  ForEach(lens.groups, id: \.category) { group in
    Section(group.category) {
      ForEach(group.items) { BookRow(book: $0) }
    }
  }
}
```

Compare with the inline-grouping anti-pattern that recomputes the
dictionary on every body evaluation:

```swift
// ❌ O(n) allocation + dictionary build + sort on every render
var body: some View {
  let groups = Dictionary(grouping: lens.items, by: \.author)
    .map { (author: $0.key, books: $0.value) }
    .sorted { $0.author < $1.author }
  List { … }
}
```

``GroupedLens`` moves that work out of the render path: it happens
once per source change or predicate update, not once per body
evaluation.

## Toggling grouping on and off

Pass `nil` to ``GroupedLens/updateCategories(_:)`` to clear the
categorizer. `items` stays populated (same filter + sort as before);
`groups` becomes empty. Views can read `items` in their flat-list path
and `groups` in their sectioned path:

```swift
if grouping == .none {
  ForEach(lens.items) { … }
} else {
  ForEach(lens.groups, id: \.category) { group in
    Section(group.category) { ForEach(group.items) { … } }
  }
}
```

This is the same lens instance either way — toggling is just a
predicate swap, not a rebuild.

## Group order

Groups are always ordered by `Category`'s `Comparable`. If your
category key is a `String`, that's lexicographic. If it's a custom
type (an enum, an `Int`, a wrapper), define `<` to match the order you
want section headers to appear in.

Items within a group inherit the lens's `sort` — one sort rule covers
both the flat list and every section.

## Performance

``GroupedLens/refresh()`` is O(n) for filter, O(n log n) for sort, and
O(n + k log k) for grouping (k = distinct categories). One pass per
source change or predicate update. Under ~1k items all three are
negligible. For larger datasets, consider whether filtering belongs in
the fetch closure (server-side via the catalog's `Criteria`) rather
than in a client-side lens.

## Refreshing against exogenous state

``GroupedLens`` automatically refreshes when its source changes or
when you call ``GroupedLens/updateFilter(_:)``,
``GroupedLens/updateSort(_:)``, or
``GroupedLens/updateCategories(_:)``. For closures that read from
state the lens cannot (or deliberately does not) observe — clocks,
locale changes, reachability, feature flags, newly-granted
permissions, cleared caches, RNG-based shuffles — call
``GroupedLens/refresh()`` to re-run the projection without changing
the closures themselves:

```swift
// Category depends on wall-clock time. The lens can't observe `Date.now`.
let lens = GroupedLens<Task, String>(
  source: catalog,
  categorize: { task in task.dueDate < .now ? "Overdue" : "Upcoming" })

// Somewhere driving a minute-tick timer:
lens.refresh()
```

For state you *can* observe, `.onChange(of:)` plus the matching
`update…` method remains the right pattern — see the next section.

## Closures capture once

``GroupedLens`` captures `filter`, `sort`, and `categorize` at init.
They re-run only on ``GroupedLens/updateFilter(_:)``,
``GroupedLens/updateSort(_:)``, ``GroupedLens/updateCategories(_:)``,
or ``GroupedLens/refresh()`` — not when observable variables they
reference change. Capturing mutable *observable* view state at init
compiles and looks correct, and fails silently:

```swift
// ❌ `grouping` capture goes stale
@State private var grouping = Grouping.author
@State private var lens = GroupedLens(
  source: catalog,
  categorize: { grouping == .author ? $0.author : $0.genre })

// ✅ Drive updates explicitly
@State private var grouping = Grouping.author
@State private var lens = GroupedLens<Book, String>(source: catalog)

var body: some View {
  BookList(lens: lens)
    .onChange(of: grouping) { _, new in
      lens.updateCategories { book in
        new == .author ? book.author : book.genre
      }
    }
}
```

Same rule as ``Catalog``'s fetch closure and ``Lens``'s predicates:
Splint closures capture at construction; mutable inputs flow through
update methods.

## Topics

### Related

- ``Catalog``
- ``Lens``
- ``Resource``
- <doc:LensGuide>
- <doc:ObservationBoundaries>
