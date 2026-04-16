# Observation boundaries

How Splint types cooperate with SwiftUI's observation system.

## Overview

`@Observable` tracks at the stored-property level, per instance. Each
view's `body` runs in its own `withObservationTracking` scope. A child
view receiving data via `init` creates an independent observation
boundary — it only tracks properties it reads in its own `body`.

### Value types (Resource structs)

No observation tracking. A child view receiving `let book: Book`
avoids re-evaluation unless the parent rebuilds and passes a
structurally different value. SwiftUI's struct diffing handles this.

### `@Observable` class instances

The child view tracks only the specific properties it reads. A detail
view and a row view can hold the *same* instance — when the detail
view changes `name`, the row view sees the change through its own
observation. No sync, no events, no propagation.

### The anti-pattern

Reading properties from an `@Observable` object inside a `ForEach`
closure. This registers the dependency on the parent view's
observation scope, making it easy to accidentally widen that scope and
trigger re-evaluation across all rows.

### The fix

Always extract `ForEach` content into a named child view. Pass data
via `init`. The child view's `body` is its own observation scope.

```swift
// ❌ Widens parent's observation scope across all rows.
ForEach(catalog.items) { item in Text(item.name) }

// ✅ Each ItemRowView has its own observation scope.
ForEach(catalog.items) { item in ItemRowView(item: item) }
```

### One store per entity, not one store per view

When both a list row and a detail view display the same entity, they
should hold the *same* `@Observable` instance. Do not create
`ItemRowStore` and `ItemDetailStore` — create one `Item` (or one
`@Model Item`) and pass it to both views. Observation boundaries form
at view boundaries automatically.

> Note: These are architectural guidelines based on how the
> Observation framework is designed to work, not guaranteed rendering
> outcomes. Apple does not document exact re-evaluation behavior. Use
> the SwiftUI Instruments template to verify performance in your
> specific app.
