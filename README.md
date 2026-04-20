# Splint

[![Certified Shovelware](https://justin.searls.co/img/shovelware.svg)](https://justin.searls.co/shovelware/)

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
| `Lens` | Filtered/sorted/grouped view over a Catalog | `@Observable` | None | Criteria mutate; data is derived |
| `Job` | Async operation lifecycle (idle → running → completed/failed) | `@Observable` | None | Phase mutates as work progresses |
| `Selection` | Currently selected item identifier | `@Observable` | None | Mutates on user tap |
| `Setting` | Single typed user preference | `@Observable` | UserDefaults | Mutates, persists automatically |
| `Credential` | Keychain-backed secret | None — read on demand | Keychain | Mutates via explicit save/delete |

**There is no `ViewState` type.** If a value doesn't fit one of the types
above, it's `@State` on the view that owns it. If two views need the
same value, make a small purpose-built `@Observable` class with 1–2
fields. If that class grows past 3 fields, you've created a new category
— name it and split it. General-purpose "view state" containers become
god-objects.

## This is not a state management framework

No reducers, no action enums, no effect types, no stores. The
architecture is SwiftUI's own — `@Query`, `@Environment`, `@State`,
`@Observable` — Splint just names the things you put in those slots.

## How observation boundaries work

`@Observable` tracks at the stored-property level, per instance. Each
view's `body` runs in its own `withObservationTracking` scope. A child
view receiving data via `init` creates an independent observation
boundary — it only tracks properties it reads in its own `body`.

- **Value types (`Resource` structs):** no observation tracking. A child
  view receiving `let book: Book` avoids re-evaluation unless the parent
  rebuilds and passes a structurally different value.
- **`@Observable` class instances:** the child view tracks only the
  specific properties it reads. A detail view and a row view can hold
  the *same instance* — when one mutates a property the other view sees
  the change through its own observation. No sync, no events.

**The anti-pattern:** reading properties from an `@Observable` object
inside a `ForEach` closure. This registers the dependency on the
parent's observation scope, widening it across the whole list.

**The fix:** always extract the row body into a named child view. Pass
data via `init`.

```swift
// ❌ Widens parent's observation scope across all rows.
ForEach(catalog.items) { item in Text(item.name) }

// ✅ Each ItemRowView has its own observation scope.
ForEach(catalog.items) { item in ItemRowView(item: item) }
```

**One store per entity, not one store per view.** When a list row and a
detail view display the same entity, they hold the same instance. Do
not create `ItemRowStore` and `ItemDetailStore`.

These are architectural guidelines based on how Observation is designed
to work, not guaranteed rendering outcomes. Use the SwiftUI Instruments
template to verify performance in your specific app.

## SwiftData entities are already correct

`@Model` includes `@Observable`. Pass instances directly to child views.
Do not wrap them in ViewModels or Splint types. Use `@Query` in views.

`@Model` types are not `Sendable` — they're bound to a `ModelContext`
and cannot cross actor boundaries, so they cannot be held in a
`Catalog`. When a view needs both `@Model` data and `Catalog` data, join
them at the view level (e.g. `@Query` for favorites, catalog lookup by
ID for the corresponding resource).

## When you *don't* need Splint

If your feature is just `@Query` → `List` → detail, write plain SwiftUI.
Splint earns its keep when you have remote API resources, async
lifecycles, preferences, or derived collections.

## Choosing the right type

- Decoded remote data → `Resource`
- Collection of Resources → `Catalog`
- Filtered/sorted view of a Catalog → `Lens`
- Async fetch lifecycle → `Job`
- Selected item identifier → `Selection`
- User preference → `Setting`
- Secret → `Credential`
- SwiftData entity → `@Model` + `@Query` (not a Splint type)
- Presentation state (sheet, alert, popover) → `@State` on the presenter
- Transition/animation state → `@State` on the animating view
- Draft/form input → `@State` on the form view
- Player/media state → dedicated `@Observable` with 1–2 fields
- Anything else shared across views → small purpose-built `@Observable`
  with 1–2 fields. If it grows past 3, name the new category and split.

There is no general-purpose "view state" container. General containers
become god-objects.

## `Catalog.load(_:)` vs `refresh()`

The most important API distinction in Splint:

- `catalog.load(newCriteria)` — criteria changed; old items are *wrong*
  (channel A's programs when you asked for channel B). Clears items
  immediately so the view shows loading, not wrong data. The one
  exception is the very first `load()`: the prior criteria was `nil`,
  so there are no "wrong" items to wipe — any seeded items from
  `initialItems:` stay visible until the fetch lands.
- `catalog.refresh()` — same criteria; items stay visible during fetch.
  This is pull-to-refresh, periodic polling, "show stale and update in
  place." No-op if `load()` has never been called.
- `catalog.retry()` — alias for `refresh()`; reads better after failure.

Pair with SwiftUI:

```swift
.task(id: channel.id) {
    catalog.load(ProgramCriteria(channelID: channel.id))
}
```

SwiftUI cancels and relaunches the task when the id changes — free
cancellation of the old fetch.

## Catalog lifecycle

Scope the catalog to the narrowest view that fully contains its usage.
Every catalog is `@State` on the owning view, distributed via
`.environment()`. The catalog lives exactly as long as that view.

- **Session-scoped** (channels for the logged-in provider): `@State` on
  the authenticated root view — *not* the app root. Logout destroys the
  authenticated root, deallocates the catalog, and cancels in-flight
  fetches via `deinit`. Logging into a different provider creates a
  fresh catalog with no stale data.
- **Navigation-scoped** (programs for a specific channel): `@State` on
  the detail view. Created on push, destroyed on pop.
- **Persistent-detail** (iPad sidebar/detail, macOS split view): `@State`
  on the detail view that survives selection changes. Driven by
  `.task(id: selectedItem.id) { catalog.load(newCriteria) }`. The
  instance persists across selections — this is where the
  criteria-clearing branch in `load()` earns its keep, preventing
  channel A's programs from showing while channel B's load.

The catalog doesn't decide its own lifecycle — SwiftUI does, based on
where you store the instance.

The fetch closure captures its dependencies at construction time. DI
happens before the Catalog exists, not after:

```swift
init(client: BookClient) {
    self._catalog = State(initialValue: Catalog(fetch: client.fetchBooks))
}
```

No singletons, no late-binding, no service locators. The same rule
applies to `Lens` filter/sort closures — see "Lens closures capture
once" below.

### Seeding from a cache

Cold launch shouldn't have to flash an empty view for the 500ms–2s the
first fetch takes. If you have a disk-cached snapshot of the last
successful fetch, pass it to `Catalog` via `initialItems:`:

```swift
let cached: [Book] = cache.load(key: "books", as: [Book].self) ?? []
let catalog = Catalog<Book, BookCriteria>(initialItems: cached) { criteria in
    try await api.fetchBooks(in: criteria.libraryID)
}
```

Semantics:

- `catalog.items` is non-empty from moment zero — any `Lens` or
  `GroupedLens` built on top sees the seed immediately.
- `catalog.phase` stays `.idle` until a real `load()` completes.
  Seeding is not a completed fetch.
- The first `load()` preserves the seed until the fetch lands, so the
  view doesn't flash empty between "we showed the cache" and "the
  network answered."

## Narrowly-scoped catalogs over client-side filtering

Large datasets should be scoped via criteria, not fetched in bulk and
filtered client-side with `Lens`:

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

The API returns programs for one channel on one date. The catalog holds
hundreds, not thousands. If you need filtering within that result (e.g.
by genre), `Lens` is appropriate at this scale.

## Lens performance

`Lens` recomputes the full filtered array when the source catalog's
items change — O(n) where n is the source size. Under ~1k items this is
negligible. For larger datasets, consider whether filtering belongs in
the fetch closure (server-side filtering via `Criteria`) rather than in
a client-side `Lens`.

## Lens closures capture once

`Lens` captures `filter` and `sort` at init. They re-run only on
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

Same rule as `Catalog`'s fetch closure: Splint closures capture at
construction; mutable inputs flow through update methods.

## Job closures and isolation

`Job.run`'s task closure runs in its own `Task`. Because `task:` is
`sending` ([SE-0430](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0430-transferring-parameters-and-results.md)),
the closure can capture non-`Sendable` values at the call site —
including `self` of a SwiftUI `View`, whose property wrappers usually
make the enclosing struct non-`Sendable`. Region-based isolation
accepts the closure's disconnected copy of the captured values.

Capture whatever's needed — a `Sendable` service, `self`'s init-time
`let` properties, a value-type input. What to avoid inside the closure
body:

- Reading `@State`, `@Query` results, or `@Environment` values from
  inside the closure body. Even when the capture compiles, you get a
  frozen snapshot taken when the closure was created — later wrapper
  updates are invisible. Capture the specific IDs or scalars you need
  at the call site instead.
- Mutating `@MainActor` state directly. The `Task` runs off the main
  actor, so the compiler usually blocks this. When you genuinely need
  to mutate main-actor state after the `await`, hop back explicitly:

```swift
metadataJob.run {
    let fresh = try await client.fetchMetadata(book.id)
    await MainActor.run { cache[book.id] = fresh }
    return fresh
}
```

```swift
// ✅ Capture self; read stable init-time `let` properties.
.task {
    metadataJob.run { try await client.fetchMetadata(book.id) }
}

// ✅ Equivalent; explicit capture for readability.
.task {
    let client = client
    let id = book.id
    metadataJob.run { try await client.fetchMetadata(id) }
}

// ❌ Reads @Query results inside the Task. `sending` may allow the
// capture, but `favorites` is a snapshot frozen at closure creation —
// later @Query updates never reach this closure. Pull what you need
// out at the call site and pass it in as a scalar.
.task {
    metadataJob.run {
        let fav = favorites.contains { $0.bookID == book.id }
        return try await client.fetchMetadata(for: book.id, favorited: fav)
    }
}
```

## Session coordination

Login, logout, and reauthentication require atomic coordination across
multiple fields (token write + provider switch + player teardown). This
is not a Splint type — it's a plain `@Observable` class with a
`login()` method that performs the coordination. It should be `@State`
on the authenticated root view and destroyed on logout. Splint types
(`Credential`, `Setting`, `Catalog`) are the *fields* it coordinates,
not a replacement for the coordinator itself.

## Settings sync across instances and processes

`Setting` observes its key via `UserDefaults` key-value observation, so:

- **Multiple instances on the same key stay in sync.** Two `Setting`s
  bound to the same key/store see each other's writes automatically.
  No "single owner per key" convention required — instance count is a
  perf footnote, not a correctness concern.
- **App Group suites sync across processes.** A `Setting` backed by
  `UserDefaults(suiteName: "group.example.shared")` stays in sync
  between the host app and its extensions (widgets, intents, share
  extensions). This is Apple's `userdefaultsd` behavior for
  entitlement-granted App Groups, surfaced through standard KVO —
  Splint adds no code of its own for cross-process notification.

## What Splint won't fix

Splint addresses data structure. It does not address SwiftUI rendering
performance (symbol effects, navigation transitions, column layout
behavior), view lifecycle timing, or platform-specific layout bugs. If
your performance problem is in the render layer, Instruments' SwiftUI
template is the right tool — not a data modeling library.

## What agents get wrong

| Agent mistake | Splint type that prevents it |
|---------------|------------------------------|
| God-object ViewModel with 15+ properties | Named types split data by kind |
| `isLoading` / `error` / `data` as separate booleans | `Job<Value>` with `phase` + `value` |
| Duplicate arrays (source + filtered copy, manually synced) | `Lens` derives from `Catalog` |
| Showing stale wrong data after parameter change | `Catalog.load()` clears items when criteria change |
| `selectedItem` on a 15-field observable | `Selection<ID>` — one value, one observation point |
| Credential stored in an observable property | `Credential` is a struct, read on demand |
| UserDefaults scattered across the app | `Setting<Value>` — one key, one observation point |
| Wrapping SwiftData models in ViewModels | Documentation: use `@Model` directly |
| Reading child properties in ForEach closure | Documentation + example: extract to child view |
| Catch-all "view state" objects that grow over time | No ViewState type exists — forces decomposition |

## Agent rules

The canonical agent guidance lives at `claude/rules/splint.md` in this
repo. See the install section above for how to drop it into a
consuming project.

## Coverage

`script/test` enforces 100% line coverage on the `Splint` target. This
is a forcing function, not a metric: if a line can't be covered by a
meaningful behavioural test, the line should be deleted, restructured
to be testable, or tagged with an inline exclusion marker whose
rationale (≥10 characters) names the specific reason:

```swift
foo()  // coverage:ignore — <why this line can't be exercised>
```

Blocks use `// coverage:ignore-start — <rationale>` and
`// coverage:ignore-end`. Padding coverage with tests that exercise a
line without verifying behaviour defeats the purpose.

## License

MIT. See `LICENSE`.
