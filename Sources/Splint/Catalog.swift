import Foundation
import Observation

/// Marker type for catalogs that require no fetch parameters.
///
/// `Void` does not conform to `Equatable` in Swift 6.3 (SE-0283 was
/// accepted but never shipped), so Splint provides a named empty struct.
/// Consumers never see `NoCriteria()` at a call site — they write
/// `catalog.load()` and `Catalog<Item, NoCriteria>(fetch:)`. The type name
/// appears only in the declaration.
public struct NoCriteria: Equatable, Sendable {
  fileprivate init() {}
}

/// An observable, ordered collection of ``Resource`` values fetched by
/// criteria, plus the fetch lifecycle.
///
/// Almost every real catalog is parameterized — channels need a provider,
/// programs need a channel, EPG entries need a channel and a date range.
/// The parameter-free case is handled by a convenience extension on
/// ``NoCriteria``.
@Observable
@MainActor
public final class Catalog<Item: Resource, Criteria: Equatable & Sendable> {
  /// Items returned by the most recent fetch, or the seed passed to
  /// ``init(initialItems:fetch:)`` before any fetch has completed.
  /// Cleared when ``load(_:)`` is called with criteria that differ from
  /// the current non-nil criteria; preserved across a first load (so
  /// seeded items stay visible until the first fetch completes) and
  /// across ``refresh()``.
  public private(set) var items: [Item] = []
  /// The criteria used for the most recent (or in-flight) load.
  public private(set) var criteria: Criteria?
  /// Fetch lifecycle phase.
  public private(set) var phase: Phase = .idle
  /// Timestamp of the last successful fetch, or `nil` if none has succeeded.
  public private(set) var lastLoaded: Date?

  @ObservationIgnored private let fetch: @Sendable (Criteria) async throws -> [Item]
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var fetchGeneration: UInt64 = 0

  /// Underlying task for the most recent fetch. Exposed under
  /// `@_spi(Internal)` so tests can assert on Task identity (e.g. that
  /// a superseded task is no longer the current one). Production
  /// callers wanting to await load completion should use
  /// ``awaitSettled()`` instead.
  @_spi(Internal)
  public var currentTask: Task<Void, Never>? { task }

  /// Suspend until the most recent ``load(_:)`` (or ``refresh()`` /
  /// ``retry()``) reaches a terminal ``Phase`` — `.completed` or
  /// `.failed`. Returns immediately if no load has been kicked off, or
  /// if the most recent load already finished.
  ///
  /// Use this to sequence "load then proceed" flows in production
  /// code: `.refreshable` closures, multi-catalog dependency chains,
  /// or cached-then-fresh launch logic.
  ///
  /// ```swift
  /// catalog.load(criteria)
  /// await catalog.awaitSettled()
  /// // catalog.items now reflects the completed (or failed) load
  /// ```
  ///
  /// Does not propagate cancellation. If the calling `Task` is
  /// cancelled mid-await, this method still waits for the in-flight
  /// load to finish — the load is owned by the catalog and continues
  /// regardless. Callers needing to bail early on cancellation should
  /// follow with `try Task.checkCancellation()`.
  public func awaitSettled() async {
    await task?.value
  }

  /// - Parameters:
  ///   - initialItems: A seed populating ``items`` before any fetch. Use
  ///     this to show a cached/snapshot copy on cold launch so consumers
  ///     of ``items`` (including ``Lens`` and ``GroupedLens``) have data
  ///     to render immediately. ``phase`` stays `.idle` until a real
  ///     ``load(_:)`` completes — seeding is not a completed fetch. The
  ///     seed remains visible through the first ``load(_:)``; it is
  ///     only cleared when ``load(_:)`` is called with criteria that
  ///     differ from an existing non-nil criteria.
  ///   - fetch: The async fetch closure invoked by ``load(_:)`` and
  ///     ``refresh()``.
  public init(
    initialItems: [Item] = [],
    fetch: @escaping @Sendable (Criteria) async throws -> [Item]
  ) {
    self.items = initialItems
    self.fetch = fetch
  }

  /// Load with `criteria`. If `criteria` differs from an existing non-nil
  /// criteria, clears ``items`` immediately so the view shows a loading
  /// state rather than wrong data from the previous criteria. The first
  /// load after init (criteria was `nil`) preserves any existing items —
  /// including seed values from ``init(initialItems:fetch:)`` — so the
  /// seed stays visible until the fetch completes.
  public func load(_ criteria: Criteria) {
    if let existing = self.criteria, existing != criteria {
      items = []
    }
    self.criteria = criteria
    performFetch(criteria)
  }

  /// Re-fetch with the current criteria. Keeps existing ``items`` visible
  /// during the fetch (pull-to-refresh, periodic polling). No-op if
  /// ``load(_:)`` has never been called.
  public func refresh() {
    guard let criteria else { return }
    performFetch(criteria)
  }

  /// Alias for ``refresh()``. Reads better after a failure:
  /// `catalog.retry()` vs `catalog.refresh()`.
  public func retry() {
    refresh()
  }

  /// Find an item by id. Convenience for detail views receiving an id from
  /// navigation.
  public subscript(id id: Item.ID) -> Item? {
    items.first { $0.id == id }
  }

  private func performFetch(_ criteria: Criteria) {
    task?.cancel()
    fetchGeneration &+= 1
    let myGeneration = fetchGeneration
    phase = .running
    task = Task { [weak self, fetch] in
      do {
        let fetched = try await fetch(criteria)
        guard let self, self.fetchGeneration == myGeneration else { return }
        self.items = fetched
        self.lastLoaded = .now
        self.phase = .completed
      } catch {
        guard let self, self.fetchGeneration == myGeneration else { return }
        self.phase = .failed(error.localizedDescription)
      }
    }
  }

  deinit { task?.cancel() }
}

extension Catalog where Criteria == NoCriteria {
  /// Convenience init for parameter-free catalogs.
  public convenience init(fetch: @escaping @Sendable () async throws -> [Item]) {
    self.init { _ in try await fetch() }
  }

  /// Load with no criteria.
  public func load() {
    load(NoCriteria())
  }
}
