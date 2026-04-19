import Foundation
import Observation

/// A derived, read-only 2-D projection over a ``Catalog``. A
/// `GroupedLens` watches its source's `items` and recomputes a
/// filtered, sorted, and optionally grouped projection when the source
/// changes or when any of the predicates change.
///
/// When the categorizer is `nil`, ``groups`` is empty and ``items``
/// behaves identically to a plain ``Lens``. When non-nil, ``groups``
/// exposes `[(category, items)]` pairs ordered by `Category`'s
/// `Comparable` conformance; items within each group preserve the
/// lens's sort order.
///
/// The source catalog's `Criteria` type is erased at init: call sites
/// see `GroupedLens<Item, Category>`, not `GroupedLens<Item, Category,
/// Criteria>`.
///
/// **Performance.** `recompute()` is O(n) for the filter pass, O(n log
/// n) for the sort (stdlib introsort) when one is set, and O(n + k log
/// k) for the grouping pass (k = distinct categories) when a
/// categorizer is set. Under ~1k items this is negligible; for larger
/// datasets, prefer server-side filtering via the catalog's `Criteria`
/// over a client-side `GroupedLens`.
@Observable
@MainActor
public final class GroupedLens<
  Item: Resource,
  Category: Hashable & Comparable & Sendable
> {
  /// The filtered and sorted projection of the source. Always
  /// populated, regardless of whether a categorizer is set.
  public private(set) var items: [Item] = []

  /// The grouped projection, ordered by `Category`'s `Comparable`.
  /// Empty when ``updateCategories(_:)`` has not been called or was
  /// last called with `nil`.
  public private(set) var groups: [(category: Category, items: [Item])] = []

  @ObservationIgnored private let sourceItems: @MainActor () -> [Item]
  @ObservationIgnored private var filter: @Sendable (Item) -> Bool
  @ObservationIgnored private var order: (@Sendable (Item, Item) -> Bool)?
  @ObservationIgnored private var categorize: (@Sendable (Item) -> Category)?

  public init<Criteria: Equatable & Sendable>(
    source: Catalog<Item, Criteria>,
    /// Predicate applied to each item. Captured once at init; re-runs
    /// only when `updateFilter` is called. Do not capture mutable view
    /// state — drive `updateFilter` from `.onChange(of:)` instead.
    filter: @escaping @Sendable (Item) -> Bool = { _ in true },
    /// Comparator applied after filtering. Same capture rules as
    /// `filter`.
    sort: (@Sendable (Item, Item) -> Bool)? = nil,
    /// Categorizer applied after sorting. When non-nil, ``groups`` is
    /// populated with one entry per distinct `Category`, ordered by
    /// `Category.<`. Items within each group preserve the lens's sort
    /// order. Pass `nil` (or omit) to leave ``groups`` empty. Same
    /// capture rules as `filter`.
    categorize: (@Sendable (Item) -> Category)? = nil
  ) {
    self.sourceItems = { source.items }
    self.filter = filter
    self.order = sort
    self.categorize = categorize
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

  /// Replace the categorizer and recompute. Pass `nil` to clear
  /// ``groups`` back to empty without losing ``items``.
  public func updateCategories(_ categorize: (@Sendable (Item) -> Category)?) {
    self.categorize = categorize
    recompute()
  }

  private func recompute() {
    var result = sourceItems().filter(self.filter)
    if let order { result.sort(by: order) }
    items = result

    guard let categorize else {
      groups = []
      return
    }
    var buckets: [Category: [Item]] = [:]
    for item in result {
      buckets[categorize(item), default: []].append(item)
    }
    groups = buckets.keys.sorted().map { key in
      (category: key, items: buckets[key]!)
    }
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
