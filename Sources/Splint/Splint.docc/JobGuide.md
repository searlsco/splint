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
    let client = client
    let id = book.id
    metadataJob.run { try await client.fetchMetadata(id) }
}
```

## Ownership and cancellation

The job owns its operation independently of the task that calls
``Job/run(priority:task:)``. Cancelling a SwiftUI `.task` does not cancel
the job. Call ``Job/cancel()`` when work must stop while its owner remains
alive. Releasing the job also cancels its current operation.

Cancellation is cooperative: the operation must observe cancellation or
use cancellation-aware APIs to stop. Capture operation inputs rather than
the job or a view that stores it. A closure retaining the job keeps it
alive, so deinitialization cannot cancel that operation until the closure
releases its reference.

Use `.task(id: book.id)` when a mounted view can receive a different book,
so the new input starts a new run and cancels the previous operation.

## Closures and isolation

``Job/run(priority:task:)``'s task closure runs in its own `Task`. Because the
parameter is `sending`
([SE-0430](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0430-transferring-parameters-and-results.md)),
the closure can capture non-`Sendable` values at the call site —
including `self` of a SwiftUI `View`, whose property wrappers usually
make the enclosing struct non-`Sendable`. Region-based isolation
accepts the closure's disconnected copy of the captured values.

Capture the specific inputs needed: a `Sendable` service, an identifier,
or another value-type input. What to avoid inside the closure
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
// ✅ Capture operation inputs without retaining the view.
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
