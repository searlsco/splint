# Credentials

A keychain-backed secret — a struct, not an `@Observable` — read on
demand at the boundary where it's needed.

## Overview

``Credential`` wraps `SecItem` with the correct add-or-update dance
and accessibility defaults. Raw keychain code is hostile, and
agent-produced implementations drift wrong in ways that compile and
appear to work on the happy path; this wrapper is the canonical form.

It is deliberately a value type. Credentials are read at the API
boundary that needs them (sign a request, hand a token to a player),
not watched by views. Storing a secret in an `@Observable` property
exposes it to every view in that observation scope and encourages
caching rules that drift out of sync with the keychain.

## Usage

```swift
let token = Credential(service: "com.example.app", account: "providerToken")

try token.save("abc123")
let value = try token.read()
try token.delete()
```

By default, ``Credential/synchronizable`` is `true` — the credential
syncs via iCloud Keychain for cross-device convenience. Pass `false`
for device-local secrets (hardware-bound tokens, device-specific keys):

```swift
let deviceKey = Credential(
    service: "com.example.app",
    account: "deviceKey",
    synchronizable: false
)
```

## Topics

### Related

- ``Setting``
- <doc:ObservationBoundaries>
