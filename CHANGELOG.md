# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
