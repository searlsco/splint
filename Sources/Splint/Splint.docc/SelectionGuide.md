# Selections

A one-value observable for the currently selected item identifier,
scoped to a single selectable concern.

## Overview

A ``Selection`` holds one optional identifier. One per concern —
active channel, active tab, highlighted row — each its own observation
boundary. The type literally cannot hold more than one value, which
structurally prevents the god-object drift you get when `selectedItem`
lives on a catch-all `@Observable` next to fourteen unrelated fields.

Store identifiers, not entities. When the view needs the full entity,
look it up via the owning ``Catalog`` or `@Query`.

## Usage

```swift
@State private var selectedChannel = Selection<Channel.ID>()

var body: some View {
    List(channels, selection: Binding(
        get: { selectedChannel.current },
        set: { selectedChannel.current = $0 }
    )) { channel in
        Text(channel.name)
    }
}
```

## Topics

### Related

- ``Catalog``
- ``Resource``
- <doc:ObservationBoundaries>
