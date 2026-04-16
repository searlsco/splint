# ``Splint``

Named data types for SwiftUI apps.

## Overview

Splint gives every data shape in your app a name so that the skeleton
heals correctly. It is *corrective, not prescriptive*: it does not
replace SwiftUI's architecture — `@Query`, `@Environment`, `@State`,
`@Observable` — it names the things you put in those slots.

Every SwiftUI app assembles views from the same handful of data shapes.
Splint names them:

- ``Resource`` — decoded remote data (channels, books, EPG entries)
- ``Catalog`` — an ordered collection of Resources loaded by criteria
- ``Lens`` — a filtered/sorted view over a Catalog
- ``Job`` — an async operation lifecycle
- ``Selection`` — the currently selected item identifier
- ``Setting`` — a single typed user preference (UserDefaults-backed)
- ``Credential`` — a keychain-backed secret

SwiftData `@Model` entities are deliberately *not* a Splint type —
`@Model` already includes `@Observable`, and `@Query` already handles
observation. Pass model instances directly to child views.

## Topics

### Modeling remote data

- ``Resource``
- ``Catalog``
- ``NoCriteria``

### Deriving views over a Catalog

- ``Lens``

### Async operation lifecycle

- ``Phase``
- ``Job``

### User-facing state

- ``Selection``
- ``Setting``
- ``SettingValue``

### Secrets

- ``Credential``
