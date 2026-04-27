# Splint Rules

Splint names the data shapes in a SwiftUI app so the skeleton heals
correctly. When you need to hold a value, consult this map before
inventing a new type.

## Map every value to a Splint type

- **Decoded remote data** (channels, books, episodes) → `struct X: Resource`.
  Conform to `Decodable` yourself when it's JSON.
- **Collection of remote data** loaded by some parameter → `Catalog<Item, Criteria>`.
  Criteria is always an `Equatable & Sendable` struct — even a single-field
  one. For the genuinely parameter-free case, `Catalog<Item, NoCriteria>`.
- **Filtered or sorted view** over a Catalog → `Lens<Item>`. It derives;
  it does not fetch. Multiple lenses can share one catalog. Filter/sort
  closures capture once at construction — drive mutable filter inputs
  through `updateFilter`/`updateSort` from `.onChange(of:)`.
- **Async operation lifecycle** (a fetch, a save, a one-off call) →
  `Job<Value>`. Not `isLoading` + `error` + `data` as separate booleans.
- **Selected item identifier** → `Selection<ID>`. One per selectable
  concern (active tab, active row, active channel). One value each.
- **User preference** (scalar only) → `Setting<Value>`. One key per
  instance. Many small settings, never a `SettingsStore` god-object.
- **Secret** (token, password) → `Credential`. A struct, read on demand.
- **SwiftData entity** → `@Model` + `@Query`. Not a Splint type. Pass
  instances directly to child views. `@Model` types are not Sendable and
  cannot live in a `Catalog` — join them at the view level.
- **Anything else shared across views** → a small purpose-built
  `@Observable` class with 1–2 fields for that specific concern. If it
  grows past 3 fields, you have combined concerns — name each and split.
  There is no general-purpose `ViewState`.
- **Anything else local to one view** → `@State` on the owning view.

## `load(_:)` vs `refresh()`

- `catalog.load(newCriteria)` — criteria changed; clears items immediately
  so the view shows loading, not wrong data.
- `catalog.refresh()` — same criteria; keeps items visible while fetching
  (pull-to-refresh, periodic polling). No-op until `load()` has been called.

Pair with SwiftUI: `.task(id: channel.id) { catalog.load(...) }` gives
you free cancellation when the id changes.

## Catalog lifecycle

Every catalog is `@State` on the narrowest view that fully contains its
usage, distributed via `.environment()`. SwiftUI owns the lifecycle —
logout destroys the authenticated root view, which deallocates the
catalog, which cancels in-flight fetches in `deinit`. Do not stash
catalogs on the app root "for convenience."

## ForEach: always extract rows

Reading an `@Observable` property inside a `ForEach` closure widens the
parent's observation scope. Always extract the row body into a named
child view that takes data via `init`. Each child's `body` is its own
observation scope.

```swift
// ❌ Parent's observation scope now covers every item's name.
ForEach(catalog.items) { item in Text(item.name) }

// ✅ Each ItemRowView has its own observation scope.
ForEach(catalog.items) { item in ItemRowView(item: item) }
```

## One store per entity, not one store per view

A list row and a detail view showing the same entity hold the *same*
`@Observable` instance (typically the same `@Model`). Do not create
`ItemRowStore` and `ItemDetailStore`. Observation boundaries form at
view boundaries automatically.

## Dependency injection

Plain protocol types or closure structs passed at `init`. The app
entry point constructs the dependency chain and captures it in the
fetch closures of catalogs. No singletons, no DI containers.

## Sharing state across views

**The default is don't.** State that powers a feature lives inside
that feature's view subtree. Most state never needs to leave. When
state must cross outward, the surface is a small, named API — never
the feature's `@Observable` itself.

**Only three things are allowed to cross a feature boundary:**

1. **Capabilities** — closures or a tiny capability struct. Actions,
   not state. `signOut: () async -> Void`,
   `playLive: (Channel) -> Void`. Closures have nothing to grow into.
2. **Coordination** — `Selection<ID>`. The agreed-upon selected item
   between sibling views. Structurally one field; cannot accrete.
3. **Events** — `AsyncStream<Enum>` or a one-shot callback. Discrete
   signals (failed-with-permission, finished, stalled).

**Never park an `@Observable` in `@Environment` so descendants can
call methods on it.** The reactive object's heartbeat reaches every
descendant — including the ones that only wanted to call a single
method. Pass a capability closure instead.

**Escalation ladder when adding shared state — stop at the first that
fits. Do not skip ahead.**

1. `@State` on the owning view. (Default. Most state never leaves.)
2. Pass via `init` to direct children. (When one child needs it, no
   reason to publish it.)
3. A Splint primitive — `Selection`, `Setting`, `Job`, `Catalog`,
   `Lens`/`GroupedLens`. (Size-bounded by design.)
4. A capability closure or struct. (Consumer wants to *do*, not
   observe.)
5. A custom `@Observable` class. **Last resort.** Justified only when
   ALL of the following hold:
   - Two views read it *today* (not "might in the future").
   - No Splint primitive fits.
   - It cannot be expressed as a closure or event.
   - It has 1–2 fields and a reason for each.

**A 1-field `@Observable` is almost always the wrong answer.** A
1-field reactive holder accretes into a 5-field god-object within a
few months. Pass the field directly, or wrap it in a `Selection` or
`Setting`.

```swift
// ❌ Reactive object parked in env so descendants can call .stop().
//    The player's heartbeat now invalidates a sidebar that only
//    wanted sign-out.
@Environment(\.playerManager) var playerManager
playerManager?.stop()

// ✅ Pass a capability.
let signOut: () async -> Void
```

```swift
// ❌ One field today; loadingTitle, loadingThumbnail, loadingChannel,
//    isCancellable six months from now.
@Observable final class LoadingTitle { var title = "" }

// ✅ Pass the value where it's needed.
struct PlayerView: View {
  let loadingTitle: String   // flowed in from the launcher
}
```

```swift
// ❌ Optional env + force-unwrap accessor in every layout file.
@Environment(\.thingy) private var thingyEnv
private var thingy: Thingy { thingyEnv! }

// ✅ Inject via init when the caller is a direct child — or give the
//    env a sentinel default if the value is a Splint primitive that
//    has one.
```
