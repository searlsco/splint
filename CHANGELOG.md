# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
