# Resources

A marker protocol bundling the conformances every decoded remote value
needs.

## Overview

``Resource`` composes `Identifiable`, `Sendable`, `Equatable`, and
`Hashable` — the conformances a value needs to appear in `ForEach`,
cross async boundaries, diff inside collections, and travel as a
`NavigationLink` value. It exists so that agents (and humans) can
write `struct Channel: Resource` instead of remembering which
protocols to adopt.

## Usage

```swift
struct Book: Resource {
    let id: String
    let title: String
    let author: String
}
```

## What's deliberately absent

`Decodable` is *not* included. Not every resource arrives from JSON —
some come from a parser, a database, or a platform API. Conformers
that need decoding add `Decodable` or `Codable` themselves.

The protocol is intentionally minimal. Adding conformances here would
force every resource in every consumer to satisfy them, for a gain
that almost never matches the cost. When a specific family of
resources needs more (for example `Sendable & Codable & Comparable`),
layer it on the concrete type.

## Topics

### Related

- ``Catalog``
- ``Lens``
