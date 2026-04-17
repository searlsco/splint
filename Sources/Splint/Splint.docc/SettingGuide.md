# Settings

A single typed user preference backed by `UserDefaults`, with live
cross-instance and cross-process sync.

## Overview

Prefer many small ``Setting`` instances over a single "settings
object." Each ``Setting`` is its own observation point, so views
reading one preference do not re-evaluate when an unrelated preference
changes. One key, one type, one observation boundary.

## Usage

```swift
let playbackRate = Setting<Double>("playbackRate", default: 1.0)
let autoplay = Setting<Bool>("autoplay", default: true)
```

`RawRepresentable` enums are supported via a convenience initializer
that reads and writes the raw value — a previously-persisted enum
setting round-trips correctly instead of silently falling back to the
default:

```swift
enum Theme: String, SettingValue { case light, dark, system }

let theme = Setting<Theme>("theme", default: .system)
```

## Sync across instances and processes

``Setting`` observes its key via `UserDefaults` key-value observation,
so:

- **Multiple instances on the same key stay in sync.** Two settings
  bound to the same key/store see each other's writes automatically.
  No "single owner per key" convention is required — instance count is
  a perf footnote, not a correctness concern.
- **App Group suites sync across processes.** A setting backed by
  `UserDefaults(suiteName: "group.example.shared")` stays in sync
  between the host app and its extensions (widgets, intents, share
  extensions). This is Apple's `userdefaultsd` behavior for
  entitlement-granted App Groups, surfaced through standard KVO —
  Splint adds no code of its own for cross-process notification.

Splint guards against KVO re-entry: when an external write delivers a
value through the observer, the setting updates `value` without
writing back. A naive round-trip would bounce indefinitely.

## Topics

### Related

- ``SettingValue``
- ``Credential``
- <doc:ObservationBoundaries>
