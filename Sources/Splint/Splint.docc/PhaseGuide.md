# Phases

The lifecycle shared by ``Catalog`` and ``Job``: idle, running,
completed, failed.

## Overview

``Phase`` is the one shared lifecycle across Splint's async types.
Both ``Catalog`` and ``Job`` expose `phase` as a stored property; a
view that cares only about *how* a fetch is going can observe `phase`
without observing the result.

Phase intentionally carries no associated result. The value produced
by a successful operation lives alongside the phase (for example
``Catalog``'s `items`, ``Job``'s `value`) so that views reading only
one need not observe the other. This is the same split that enables
fine-grained observation elsewhere in the library: separate fields,
separate boundaries.

## Cases

- ``Phase/idle`` — no work has started.
- ``Phase/running`` — work is in flight.
- ``Phase/completed`` — work finished successfully.
- ``Phase/failed(_:)`` — work failed. The associated value is a
  user-presentable message.

The failure associated value is a plain `String`, deliberately. A
`Phase` needs to be `Equatable` and `Sendable`, and views almost
always want to show a message, not introspect an error type. When a
caller needs structured diagnostics, surface them alongside the phase
rather than inside it.

## Topics

### Related

- ``Catalog``
- ``Job``
