# Cloud sync

Mirror chosen `UserDefaults` keys into iCloud key-value storage so
`Setting`s sync across a user's devices.

## Overview

``CloudSync`` mirrors a declared set of `UserDefaults` keys into
`NSUbiquitousKeyValueStore`. Every ``Setting`` bound to a mirrored key
syncs across the user's devices — and, when two apps declare the same
ubiquity key-value store identifier in their entitlements, across apps.

```swift
let cloudSync = CloudSync(keys: ["playbackRate", "theme"])
cloudSync.start()
```

Hold one instance for the app's lifetime and call ``CloudSync/start()``
at launch. `Setting` already observes `UserDefaults`, so pulled changes
propagate to live `Setting` instances (and their views) with no further
wiring.

## The invariant: upload only on explicit mutation

Nothing writes to iCloud unless the app explicitly assigns a mirrored
`Setting`'s `value` or calls its `reset()`. Everything else is
receive-only:

- **Startup** pulls whatever iCloud has already delivered, then waits.
  Cloud values and deletions arriving later — the initial download can
  take arbitrarily long — apply whenever their notification lands.
- **A local-only value stays local** until the user next changes it. A
  fresh install can never clobber a real cloud preference with a
  locally-seeded default.
- **Direct `UserDefaults` writes never upload.** Only a `Setting`
  mutation counts as intent.
- Conflicts are last-writer-wins (iCloud's own semantics).

Consequences worth knowing:

- **A preference that predates mirroring uploads on its next explicit
  change**, not at startup. To publish a current local value without
  changing it, reassign it: `setting.value = setting.value`.
- **Mutations made before `start()` stay local** until the next
  mutation after `start()`. Start CloudSync at launch, before settings
  UI is reachable.
- **`reset()` is cloud-wide.** It removes the ubiquitous key, so every
  device falls back to its declared default. A "restore defaults"
  button that resets mirrored keys resets them for the whole account —
  which is usually exactly what the user meant, but worth knowing.
- **There is no upload retry.** If an upload can't be recorded (signed
  out of iCloud, quota exceeded), the value stays local and the next
  explicit mutation tries again.

## One store instance

Pass the same `UserDefaults` **instance** to `CloudSync` and to every
mirrored `Setting`. With the default `.standard` (a singleton) this is
automatic. For an App Group suite, create one
`UserDefaults(suiteName:)` and share it — mutation signals are matched
by instance identity, and a second instance of the same suite is
silently unrecognized. Cross-process App Group mutations (from an
extension) do not reach the host app's `CloudSync`; run mirroring in
the process that mutates.

## Topics

- ``CloudSync``
- ``UbiquitousKeyValueStore``
