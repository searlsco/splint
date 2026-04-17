# Setting values

The marker protocol identifying value types that ``Setting`` can
persist safely through `UserDefaults`.

## Overview

``SettingValue`` constrains ``Setting``'s generic parameter to types
that `UserDefaults` supports natively. The protocol refines
`Sendable & Equatable`, so every persisted preference can cross actor
boundaries and suppress redundant observation cycles when an external
KVO callback delivers a value that already matches.

Conforming types:

- `Bool`, `Int`, `Double`, `Float`
- `String`, `Data`, `Date`
- `Array<Element>` where `Element: SettingValue`
- `Dictionary<String, Value>` where `Value: SettingValue`

A ``Setting`` whose `Value` is a `RawRepresentable` enum whose
`RawValue` conforms to ``SettingValue`` gets a convenience initializer
that reads and writes via `rawValue`.

## What's deliberately absent

- **`URL`** — `UserDefaults` archives URLs via `NSKeyedArchiver`, so
  a plain `object(forKey:) as? URL` round-trip fails silently. Store
  URLs as `String` and parse at the boundary that needs them.
- **`Codable` structs** — encoding arbitrary structs into `Data` and
  stashing them in `UserDefaults` is an anti-pattern. It bypasses the
  store's schema guarantees, makes migrations implicit, and blurs the
  line between user preferences and app state. Use SwiftData for
  structured persistence.

Both exclusions are deliberate, not oversights. Widening the protocol
would make the wrong thing easy.

## Topics

### Related

- ``Setting``
