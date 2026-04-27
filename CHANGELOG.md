# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.6.0] - 2026-04-27

### Added

- `Catalog.awaitSettled()` and `Job.awaitSettled()` — public async
  primitives that suspend until the catalog/job reaches a settled
  `Phase` (`.completed` or `.failed`). Replaces the
  `@_spi(Internal) currentTask?.value` pattern for production
  sequencing of "load then proceed" flows: `.refreshable` closures,
  multi-catalog dependency chains, and cached-then-fresh launch
  logic. Tracks supersedes — if a load/run is cancelled and replaced
  by another while suspended, the method continues waiting until the
  catalog/job ultimately stops loading, not when the cancelled task
  resolves. Non-throwing; does not propagate cancellation
  ([#34](https://github.com/searlsco/splint/issues/34)).
- `Job.currentTask` exposed under `@_spi(Internal)` for tests that
  need to synchronize on the specific task instance, mirroring
  `Catalog.currentTask`.

## [0.5.0] - 2026-04-24

### Added

- `GroupedLens` categorizer overload that receives the raw source
  collection alongside the filtered+sorted visible one:
  `(Item, _ visible: [Item], _ source: [Item]) -> Category`. Enables
  bucketing anchored to the source (e.g. "above the library-wide mean"
  while the lens is filtered to a subset) without reaching outside the
  lens. Available on both `init` and `updateCategories(_:)`; the
  existing one- and two-argument forms are unchanged.

## [0.4.0] - 2026-04-24

### Added

- `GroupedLens` categorizer overload that receives the full
  filtered+sorted collection alongside each item:
  `(Item, [Item]) -> Category`. Enables aggregate-aware bucketing
  (percentiles, above/below median, rank-based groups) without
  precomputing aggregates outside the lens. Available on both `init`
  and `updateCategories(_:)`; the existing `(Item) -> Category` form
  is unchanged and remains the default.
- `Lens.refresh()` and `GroupedLens.refresh()` — public entry points
  that re-run the current filter, sort, and (for `GroupedLens`)
  categorizer over the source catalog's items without changing the
  closures themselves. Intended for predicates that read from state
  the lens cannot practically observe: clocks (`Date.now`,
  time-windowed filters), locale changes, reachability / online
  status, feature flags, newly-granted permissions, cleared caches,
  and RNG-based shuffles. Previously this required calling
  `updateFilter` (or `updateSort` / `updateCategories`) with an
  identical closure
  ([#31](https://github.com/searlsco/splint/pull/31)).

### Changed

- `Lens` and `GroupedLens` init-parameter documentation: the "do not
  capture mutable view state" warning now scopes to *observable* view
  state and points at `refresh()` as the escape hatch for exogenous
  state. The underlying advice (observable inputs flow through
  `.onChange(of:)` + `updateFilter`) is unchanged; the guidance just
  no longer discourages legitimate exogenous-state patterns.

## [0.3.0] - 2026-04-20

### Added

- `Catalog.init(initialItems:fetch:)` — seed a catalog with a snapshot
  so `items` is non-empty from moment zero. Lets consumers show a
  disk-cached copy immediately on cold launch instead of flashing an
  empty state while the first fetch runs. `Lens` and `GroupedLens`
  built on top see the seed immediately. `phase` stays `.idle` until
  a real `load()` completes
  ([#29](https://github.com/searlsco/splint/issues/29)).

### Changed

- `Catalog.load(_:)` now preserves `items` on the first load (when
  the prior criteria was `nil`) instead of clearing them. Clearing on
  criteria change still applies when transitioning between two
  distinct non-nil criteria. This is what makes `initialItems:` seeds
  stay visible through the first fetch.

## [0.2.0] - 2026-04-19

### Added

- `GroupedLens<Item, Category>` — a new sibling projection type
  alongside `Lens<Item>` for sectioned lists. Exposes both the
  filter+sort output (`items`) and a cached grouped form
  (`groups: [(category: Category, items: [Item])]`) derived from an
  optional `@Sendable (Item) -> Category` categorizer. Groups are
  ordered by `Category`'s `Comparable`; items within each group
  preserve the lens's sort. Enables `ForEach { Section }` SwiftUI
  patterns without per-render `Dictionary(grouping:)`
  ([#26](https://github.com/searlsco/splint/issues/26)).

## [0.1.0] - 2026-04-17

### Added

- Initial public API: `Resource`, `Catalog`, `Lens`, `Job`, `Phase`,
  `Selection`, `Setting`, `SettingValue`, `Credential`, `NoCriteria`.
- Agent rules at `claude/rules/splint.md`.
- README install instructions for dropping `claude/rules/splint.md`
  into a consuming project via `curl`.
- `Setting` now observes its key via `UserDefaults` KVO. Multiple
  `Setting` instances bound to the same key/store stay in sync
  automatically, and App Group suites stay in sync across the host
  app and its extensions via `userdefaultsd`.

### Changed

- `SettingValue` now requires `Equatable` (in addition to `Sendable`).
  Every built-in conformer is already `Equatable`, so existing
  conformances continue to work; user-defined conformers must add it.
