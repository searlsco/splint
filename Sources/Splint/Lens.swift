import Foundation
import Observation

/// A derived, read-only view over a ``Catalog``. A `Lens` watches its
/// source's `items` and recomputes its own filtered/sorted projection when
/// the source changes, or when the filter/sort predicates change.
///
/// The source catalog's `Criteria` type is erased at init: call sites see
/// `Lens<Channel>`, not `Lens<Channel, ProviderCriteria>`.
///
/// **Performance.** `refresh()` is O(n) for the filter pass plus
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
    /// when ``updateFilter(_:)`` or ``refresh()`` is called. Do not capture
    /// mutable *observable* view state — drive ``updateFilter(_:)`` from
    /// `.onChange(of:)` instead. For exogenous state the lens cannot
    /// practically observe (clocks, locale, reachability, feature flags,
    /// newly-granted permissions, cleared caches, RNG) it's fine for the
    /// closure to read that state directly; call ``refresh()`` to re-run
    /// the projection when it changes.
    filter: @escaping @Sendable (Item) -> Bool = { _ in true },
    /// Comparator applied after filtering. Same capture rules as `filter`.
    sort: (@Sendable (Item, Item) -> Bool)? = nil
  ) {
    self.sourceItems = { source.items }
    self.filter = filter
    self.order = sort
    refresh()
    observe()
  }

  /// Replace the filter predicate and recompute.
  public func updateFilter(_ filter: @escaping @Sendable (Item) -> Bool) {
    self.filter = filter
    refresh()
  }

  /// Replace the sort predicate and recompute. Pass `nil` to remove
  /// sorting and return to source order.
  public func updateSort(_ sort: (@Sendable (Item, Item) -> Bool)?) {
    self.order = sort
    refresh()
  }

  /// Re-run the current filter and sort over the source catalog's items
  /// without changing the closures themselves. The lens automatically
  /// refreshes when the source changes or when you call
  /// ``updateFilter(_:)`` / ``updateSort(_:)`` — reach for `refresh()`
  /// only when the filter or sort closure reads from state the lens
  /// cannot (or deliberately does not) observe: clocks (`Date.now`,
  /// "due within the next hour"), locale changes, reachability / online
  /// status, file-system mtimes, feature flags, newly-granted
  /// permissions, cleared caches, or RNG-based shuffles. For state you
  /// *can* observe, `.onChange(of:)` plus ``updateFilter(_:)`` remains
  /// the right pattern.
  public func refresh() {
    var result = sourceItems().filter(self.filter)
    if let order { result.sort(by: order) }
    items = result
  }

  private func observe() {
    // Re-arm tracking on every change. onChange fires *before* the mutation
    // is committed, so defer the refresh to the next MainActor hop.
    withObservationTracking { [weak self] in
      _ = self?.sourceItems()
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.refresh()
        self.observe()
      }
    }
  }
}
