import Observation

/// The currently selected item identifier for a single selectable concern.
///
/// One ``Selection`` per concern (active channel, active tab, highlighted
/// row). Each is its own observation boundary; the type literally cannot
/// hold more than one value, which structurally prevents god-object drift.
@Observable
@MainActor
public final class Selection<ID: Hashable & Sendable> {
  /// The currently selected identifier, or `nil` if nothing is selected.
  public var current: ID?

  /// Create an empty selection.
  ///
  /// Construction is `nonisolated`; property reads and writes remain
  /// `@MainActor`. This lets `Selection` be used as the
  /// `defaultValue` of a SwiftUI `EnvironmentKey`, which is read from
  /// nonisolated contexts.
  public nonisolated init() {}

  /// Create a selection seeded with an initial value.
  public init(_ initial: ID?) {
    self.current = initial
  }
}
