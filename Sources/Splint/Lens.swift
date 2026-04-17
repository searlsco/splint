import Foundation
import Observation

/// A derived, read-only view over a ``Catalog``. A `Lens` watches its
/// source's `items` and recomputes its own filtered/sorted projection when
/// the source changes, or when the filter/sort predicates change.
///
/// The source catalog's `Criteria` type is erased at init: call sites see
/// `Lens<Channel>`, not `Lens<Channel, ProviderCriteria>`.
///
/// **Performance.** `recompute()` is O(n) for the filter pass plus
/// O(n log n) for the sort (stdlib introsort) when one is set. Under ~1k
/// items this is negligible; for larger datasets, prefer server-side
/// filtering via the catalog's `Criteria` over a client-side `Lens`.
@Observable
@MainActor
public final class Lens<Item: Resource> {
  /// The filtered and sorted projection of the source.
  public private(set) var items: [Item] = []

  @ObservationIgnored private let sourceItems: @MainActor () -> [Item]
  @ObservationIgnored private var filter: @Sendable (Item) -> Bool
  @ObservationIgnored private var order: (@Sendable (Item, Item) -> Bool)?
  public init<Criteria: Equatable & Sendable>(
    source: Catalog<Item, Criteria>,
    /// Predicate applied to each item. Captured once at init; re-runs only
    /// when `updateFilter` is called. Do not capture mutable view state —
    /// drive `updateFilter` from `.onChange(of:)` instead.
    filter: @escaping @Sendable (Item) -> Bool = { _ in true },
    /// Comparator applied after filtering. Same capture rules as `filter`.
    sort: (@Sendable (Item, Item) -> Bool)? = nil
  ) {
    self.sourceItems = { source.items }
    self.filter = filter
    self.order = sort
    recompute()
    observe()
  }

  /// Replace the filter predicate and recompute.
  public func updateFilter(_ filter: @escaping @Sendable (Item) -> Bool) {
    self.filter = filter
    recompute()
  }

  /// Replace the sort predicate and recompute. Pass `nil` to remove
  /// sorting and return to source order.
  public func updateSort(_ sort: (@Sendable (Item, Item) -> Bool)?) {
    self.order = sort
    recompute()
  }

  private func recompute() {
    var result = sourceItems().filter(self.filter)
    if let order { result.sort(by: order) }
    items = result
  }

  private func observe() {
    // Re-arm tracking on every change. onChange fires *before* the mutation
    // is committed, so defer the recompute to the next MainActor hop.
    withObservationTracking { [weak self] in
      _ = self?.sourceItems()
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.recompute()
        self.observe()
      }
    }
  }
}
