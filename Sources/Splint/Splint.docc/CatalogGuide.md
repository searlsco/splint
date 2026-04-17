# Catalogs of remote resources

An observable, ordered collection of ``Resource`` values fetched by
criteria, plus the fetch lifecycle.

## Overview

Almost every real catalog is parameterized — channels need a provider,
programs need a channel, EPG entries need a channel and a date range. A
``Catalog`` bundles the collection, the criteria that produced it, and
the fetch lifecycle into a single `@Observable` whose fields are
observed independently.

The parameter-free case is handled by a convenience on ``NoCriteria``:
call `catalog.load()` with no argument.

## Usage

```swift
struct BookCriteria: Equatable, Sendable {
    let libraryID: String
}

let catalog = Catalog<Book, BookCriteria> { criteria in
    try await api.fetchBooks(in: criteria.libraryID)
}

catalog.load(BookCriteria(libraryID: "main"))
```

Pair with SwiftUI:

```swift
.task(id: channel.id) {
    catalog.load(ProgramCriteria(channelID: channel.id))
}
```

SwiftUI cancels and relaunches the task when the id changes — free
cancellation of the old fetch.

## `load(_:)` vs `refresh()`

The most important API distinction in Splint:

- `catalog.load(newCriteria)` — criteria changed; old items are *wrong*
  (channel A's programs when you asked for channel B). Clears items
  immediately so the view shows loading, not wrong data.
- `catalog.refresh()` — same criteria; items stay visible during fetch.
  This is pull-to-refresh, periodic polling, "show stale and update in
  place." No-op if `load()` has never been called.
- `catalog.retry()` — alias for `refresh()`; reads better after
  failure.

## Catalog lifecycle

Scope the catalog to the narrowest view that fully contains its usage.
Every catalog is `@State` on the owning view, distributed via
`.environment()`. The catalog lives exactly as long as that view.

- **Session-scoped** (channels for the logged-in provider): `@State` on
  the authenticated root view — *not* the app root. Logout destroys
  that root, deallocates the catalog, and cancels in-flight fetches via
  `deinit`. Logging into a different provider creates a fresh catalog
  with no stale data.
- **Navigation-scoped** (programs for a specific channel): `@State` on
  the detail view. Created on push, destroyed on pop.
- **Persistent-detail** (iPad sidebar/detail, macOS split view):
  `@State` on the detail view that survives selection changes. Driven
  by `.task(id: selectedItem.id) { catalog.load(newCriteria) }`. The
  instance persists across selections — this is where the
  criteria-clearing branch in `load()` earns its keep, preventing
  channel A's programs from showing while channel B's load.

The catalog doesn't decide its own lifecycle — SwiftUI does, based on
where you store the instance.

## Dependency injection happens at init

The fetch closure captures its dependencies at construction time. DI
happens before the Catalog exists, not after:

```swift
init(client: BookClient) {
    self._catalog = State(initialValue: Catalog(fetch: client.fetchBooks))
}
```

No singletons, no late-binding, no service locators. The same rule
applies to ``Lens`` filter/sort closures.

## Narrowly-scoped catalogs over client-side filtering

Large datasets should be scoped via criteria, not fetched in bulk and
filtered client-side with ``Lens``:

```swift
struct ProgramGuideView: View {
    let channel: Channel
    @State private var programs: Catalog<Program, ScheduleCriteria>

    init(channel: Channel, api: IPTVClient) {
        self.channel = channel
        self._programs = State(initialValue: Catalog { criteria in
            try await api.fetchPrograms(for: criteria.channelID, on: criteria.date)
        })
    }

    var body: some View {
        ProgramList(programs: programs)
            .task {
                programs.load(ScheduleCriteria(channelID: channel.id, date: .now))
            }
    }
}
```

The API returns programs for one channel on one date. The catalog
holds hundreds, not thousands. If you need filtering within that
result (e.g. by genre), ``Lens`` is appropriate at this scale.

## Topics

### Related

- ``Resource``
- ``Lens``
- ``Phase``
- ``NoCriteria``
- <doc:ObservationBoundaries>
