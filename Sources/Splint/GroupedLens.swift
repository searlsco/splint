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
/// **Performance.** `refresh()` is O(n) for the filter pass, O(n log
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
  public private(set) var items: [Item] = [] {
    didSet { rebuildItemsByID() }
  }

  /// The grouped projection, ordered by `Category`'s `Comparable`.
  /// Empty when ``updateCategories(_:)`` has not been called or was
  /// last called with `nil`.
  public private(set) var groups: [(category: Category, items: [Item])] = []

  @ObservationIgnored private let sourceItems: @MainActor () -> [Item]
  @ObservationIgnored private var filter: @Sendable (Item) -> Bool
  @ObservationIgnored private var order: (@Sendable (Item, Item) -> Bool)?
  @ObservationIgnored private var categorize: (@Sendable (Item, [Item], [Item]) -> Category)?
  @ObservationIgnored private var itemsByID: [Item.ID: Item] = [:]

  public init<Criteria: Equatable & Sendable>(
    source: Catalog<Item, Criteria>,
    /// Predicate applied to each item. Captured once at init; re-runs
    /// only when ``updateFilter(_:)`` or ``refresh()`` is called. Do not
    /// capture mutable *observable* view state — drive
    /// ``updateFilter(_:)`` from `.onChange(of:)` instead. For exogenous
    /// state the lens cannot practically observe (clocks, locale,
    /// reachability, feature flags, newly-granted permissions, cleared
    /// caches, RNG) it's fine for the closure to read that state
    /// directly; call ``refresh()`` to re-run the projection when it
    /// changes.
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
    self.categorize = categorize.map { simple -> @Sendable (Item, [Item], [Item]) -> Category in
      { item, _, _ in simple(item) }
    }
    refresh()
    observe()
  }

  /// Aggregate-aware variant. The categorizer receives the current item
  /// *and* the full filtered+sorted collection, enabling bucketing that
  /// depends on aggregates (percentiles, above/below median, rank).
  /// `visible` is the same array exposed as ``items``; it has already
  /// had `filter` and `sort` applied. Use the three-argument overload
  /// when aggregates should be computed from the raw source instead.
  public init<Criteria: Equatable & Sendable>(
    source: Catalog<Item, Criteria>,
    filter: @escaping @Sendable (Item) -> Bool = { _ in true },
    sort: (@Sendable (Item, Item) -> Bool)? = nil,
    categorize: @escaping @Sendable (_ item: Item, _ visible: [Item]) -> Category
  ) {
    self.sourceItems = { source.items }
    self.filter = filter
    self.order = sort
    self.categorize = { item, visible, _ in categorize(item, visible) }
    refresh()
    observe()
  }

  /// Source-aware variant. The categorizer receives the current item,
  /// the filtered+sorted `visible` collection (same as ``items``), and
  /// the raw `source` collection from the catalog (before filtering or
  /// sorting). Use when bucketing must be anchored to the source — e.g.
  /// "above the library-wide mean" while the lens is filtered to a
  /// subset.
  public init<Criteria: Equatable & Sendable>(
    source: Catalog<Item, Criteria>,
    filter: @escaping @Sendable (Item) -> Bool = { _ in true },
    sort: (@Sendable (Item, Item) -> Bool)? = nil,
    categorize: @escaping @Sendable (_ item: Item, _ visible: [Item], _ source: [Item]) -> Category
  ) {
    self.sourceItems = { source.items }
    self.filter = filter
    self.order = sort
    self.categorize = categorize
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

  /// Replace the categorizer and recompute. Pass `nil` to clear
  /// ``groups`` back to empty without losing ``items``.
  public func updateCategories(_ categorize: (@Sendable (Item) -> Category)?) {
    self.categorize = categorize.map { simple -> @Sendable (Item, [Item], [Item]) -> Category in
      { item, _, _ in simple(item) }
    }
    refresh()
  }

  /// Aggregate-aware variant of ``updateCategories(_:)``. The closure
  /// receives the current item and the filtered+sorted `visible`
  /// collection (same as ``items``).
  public func updateCategories(
    _ categorize: @escaping @Sendable (_ item: Item, _ visible: [Item]) -> Category
  ) {
    self.categorize = { item, visible, _ in categorize(item, visible) }
    refresh()
  }

  /// Source-aware variant of ``updateCategories(_:)``. The closure
  /// receives the current item, the filtered+sorted `visible`
  /// collection, and the raw `source` collection from the catalog.
  public func updateCategories(
    _ categorize: @escaping @Sendable (_ item: Item, _ visible: [Item], _ source: [Item]) -> Category
  ) {
    self.categorize = categorize
    refresh()
  }

  /// Re-run the current filter, sort, and categorizer over the source
  /// catalog's items without changing the closures themselves. The
  /// lens automatically refreshes when the source changes or when you
  /// call ``updateFilter(_:)`` / ``updateSort(_:)`` /
  /// ``updateCategories(_:)`` — reach for `refresh()` only when any of
  /// those closures reads from state the lens cannot (or deliberately
  /// does not) observe: clocks (`Date.now`, "due within the next
  /// hour"), locale changes, reachability / online status, file-system
  /// mtimes, feature flags, newly-granted permissions, cleared caches,
  /// or RNG-based shuffles. Both ``items`` and ``groups`` are
  /// recomputed. For state you *can* observe, `.onChange(of:)` plus
  /// the matching `update…` method remains the right pattern.
  public func refresh() {
    let source = sourceItems()
    var result = source.filter(self.filter)
    if let order { result.sort(by: order) }
    items = result

    guard let categorize else {
      groups = []
      return
    }
    var buckets: [Category: [Item]] = [:]
    for item in result {
      buckets[categorize(item, result, source), default: []].append(item)
    }
    groups = buckets.keys.sorted().map { key in
      (category: key, items: buckets[key]!)
    }
  }

  /// Find an item by id within the lens's filtered projection. O(1).
  /// Returns `nil` if `id` is not present in ``items`` after filtering —
  /// even if it exists in the source catalog. When the projection
  /// contains multiple entries with the same id, the first occurrence
  /// wins.
  public subscript(id id: Item.ID) -> Item? {
    _ = items
    return itemsByID[id]
  }

  private func rebuildItemsByID() {
    itemsByID = Dictionary(items.lazy.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
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
