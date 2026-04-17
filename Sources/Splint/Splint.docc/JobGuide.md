# Jobs for one-shot async work

An observable async-operation lifecycle. Replaces the ad hoc
`isLoading` / `error` / `data` trio that tends to drift onto a view
model and become a god-object seed.

## Overview

``Job`` exposes two stored properties — ``Job/phase`` (lifecycle) and
``Job/value`` (result) — that are observed independently. Views reading
only one do not re-evaluate when the other changes.

## Usage

```swift
let metadataJob = Job<Metadata>()

.task {
    metadataJob.run { try await client.fetchMetadata(book.id) }
}
```

## Closures and isolation

``Job/run(_:)``'s task closure runs in its own `Task`. Because the
parameter is `sending`
([SE-0430](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0430-transferring-parameters-and-results.md)),
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

Patterns that work well:

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

## Topics

### Related

- ``Phase``
- ``Catalog``
- <doc:ObservationBoundaries>
