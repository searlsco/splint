# Sharing state across views

What crosses out of a feature's view subtree — and what stays in.

## Overview

A feature owns a chunk of state — a player's transport, a list view's
filter inputs, a sign-in flow's draft form. Most of that state never
needs to leave the feature's view subtree. The temptation is to publish
it anyway: park the `@Observable` in `@Environment` so a sibling can
call a method on it, or hold "just the one shared field" in a tiny
custom `@Observable`. Both lead to the same place — a reactive object
broadcasting property changes that downstream views don't actually
read.

The fix is to treat the cross-boundary surface as a public API: small,
named, and resistant to growth.

## The cross-boundary surface

When state must cross outward from a feature, exactly three primitives
appear at the boundary.

### Capabilities — closures or a tiny capability struct

Actions, not state. When a parent or sibling wants the feature *to do*
something — sign out, stop playback, retry an upload — pass a closure,
or a small struct of closures, down through `init`. Closures have
nothing to grow into; they cannot accrete a stray property six months
from now.

```swift
// The sign-out site doesn't need to observe the player; it needs to
// stop it.
struct PlaybackLauncher {
    var stop: () -> Void
    var play: (Channel) -> Void
}
```

### Coordination — ``Selection``

When two views need to agree on "which X is currently the relevant
one" — playing item, focused row, drilled-in section — the answer is a
``Selection``. It is structurally one field; it cannot accrete
properties. Sibling views read `selection.current` instead of observing
the feature's reactive state.

### Events — `AsyncStream` or a one-shot callback

Discrete signals — finished, failed-with-permission, stalled — flow as
events, not as observable properties. Other views attach to the stream,
or accept a callback at `init`. Events are observed by attaching, not
by polling reactive properties.

## The escalation ladder

When introducing new shared state, apply in order. Stop at the first
that fits.

1. **`@State` on the owning view.** Default. Most state never needs to
   leave.
2. **Pass via `init` to direct children.** When one child needs the
   value, there is no reason to publish it for everyone.
3. **A Splint primitive** — ``Selection``, ``Setting``, ``Job``,
   ``Catalog``, ``Lens``/``GroupedLens``. Each one is size-bounded by
   design.
4. **A capability closure or struct.** When the consumer wants to *do*
   something, not observe ticks.
5. **A custom `@Observable` class.** Last resort. Justified only when:
   - Two views read it *today* (not "might in future").
   - No Splint primitive fits.
   - It cannot be expressed as a closure or event.
   - It has 1–2 fields and a reason for each.

## Anti-patterns

### Reading a feature's reactive object from `@Environment`

```swift
// ❌ The player's heartbeat reaches every descendant — most of which
//    only needed to call .stop() during sign-out.
@Environment(\.playerManager) var playerManager
playerManager?.stop()

// ✅ Pass a capability.
let signOut: () async -> Void
```

### A 1-field `@Observable` for "the one shared value"

```swift
// ❌ One field today; loadingTitle, loadingThumbnail, loadingChannel,
//    isCancellable six months from now.
@Observable final class LoadingTitle { var title = "" }

// ✅ Pass the value where it's needed.
struct PlayerView: View {
    let loadingTitle: String
}
```

### Force-unwrapping an optional environment value

```swift
// ❌ Optional env + force-unwrap accessor in every layout file.
@Environment(\.thingy) private var thingyEnv
private var thingy: Thingy { thingyEnv! }

// ✅ Either inject via init when the caller is a direct child — or
//    give the env a sentinel default when the value is a Splint
//    primitive that has one.
```

## Topics

### Related

- <doc:ChoosingTheRightType>
- <doc:ObservationBoundaries>
- ``Selection``
- ``Setting``
