# Choosing the right type

A decision guide for picking a Splint primitive — or deliberately not
picking one.

## Overview

Every SwiftUI app assembles views from the same handful of data shapes.
Splint names them. The library is *corrective, not prescriptive*: it
does not replace SwiftUI's architecture, it names the things you put
into `@State`, `@Environment`, `@Query`, and `@Observable`.

## The type inventory

| Type | What it holds | Observation | Persistence | Mutability |
|------|---------------|-------------|-------------|------------|
| ``Resource`` | Decoded remote data | None — value type | None | Immutable after decode |
| ``Catalog`` | Ordered collection of Resources loaded by criteria, plus fetch lifecycle | `@Observable` | None (in-memory cache) | Collection mutates on load/refresh |
| ``Lens`` | Filtered/sorted/grouped view over a ``Catalog`` | `@Observable` | None | Criteria mutate; data is derived |
| ``Job`` | Async operation lifecycle | `@Observable` | None | Phase mutates as work progresses |
| ``Selection`` | Currently selected item identifier | `@Observable` | None | Mutates on user tap |
| ``Setting`` | Single typed user preference | `@Observable` | UserDefaults | Mutates, persists automatically |
| ``Credential`` | Keychain-backed secret | None — read on demand | Keychain | Mutates via explicit save/delete |

## Decision guide

- Decoded remote data → ``Resource``
- Collection of Resources → ``Catalog``
- Filtered/sorted view of a Catalog → ``Lens``
- Async fetch lifecycle → ``Job``
- Selected item identifier → ``Selection``
- User preference → ``Setting``
- Secret → ``Credential``
- SwiftData entity → `@Model` + `@Query` (*not* a Splint type)
- Presentation state (sheet, alert, popover) → `@State` on the presenter
- Transition/animation state → `@State` on the animating view
- Draft/form input → `@State` on the form view
- Player/media state → dedicated `@Observable` with 1–2 fields
- Anything else shared across views → small purpose-built `@Observable`
  with 1–2 fields. If it grows past 3 fields, you've discovered a new
  category — name it and split it.

## There is no `ViewState` type

If a value doesn't fit one of the types above, it is `@State` on the
view that owns it. If two views need the same value, make a small
purpose-built `@Observable` class with 1–2 fields. A general-purpose
"view state" container becomes a god-object over time; forcing
decomposition is the point.

## When you *don't* need Splint

If your feature is just `@Query` → `List` → detail, write plain
SwiftUI. Splint earns its keep when you have remote API resources,
async lifecycles, preferences, or derived collections.

## SwiftData entities are already correct

`@Model` includes `@Observable`. Pass instances directly to child
views. Do not wrap them in ViewModels or Splint types. Use `@Query` in
views. `@Model` types are not `Sendable` and cannot be held in a
``Catalog``; join `@Query` results with catalog lookups at the view
level when both are needed.

## Topics

### Related

- <doc:ObservationBoundaries>
