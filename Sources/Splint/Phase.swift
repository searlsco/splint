/// Lifecycle of an async operation. Shared by ``Catalog`` and ``Job``.
///
/// ``Phase`` intentionally carries no associated result. The value produced by
/// a successful operation lives alongside the phase (e.g. `Catalog.items`,
/// `Job.value`) so that views reading only one need not observe the other.
public enum Phase: Sendable, Equatable {
  /// No work has started.
  case idle
  /// Work is in flight.
  case running
  /// Work finished successfully.
  case completed
  /// Work failed. The associated value is a user-presentable message.
  case failed(String)
}
