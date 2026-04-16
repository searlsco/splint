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
  /// Items returned by the most recent fetch. Cleared when criteria change
  /// in ``load(_:)``; preserved when ``refresh()`` is called with the same
  /// criteria.
  public private(set) var items: [Item] = []
  /// The criteria used for the most recent (or in-flight) load.
  public private(set) var criteria: Criteria?
  /// Fetch lifecycle phase.
  public private(set) var phase: Phase = .idle
  /// Timestamp of the last successful fetch, or `nil` if none has succeeded.
  public private(set) var lastLoaded: Date?

  @ObservationIgnored private let fetch: @Sendable (Criteria) async throws -> [Item]
  @ObservationIgnored private var task: Task<Void, Never>?

  public init(fetch: @escaping @Sendable (Criteria) async throws -> [Item]) {
    self.fetch = fetch
  }

  /// Load with `criteria`. If the criteria differ from the current ones,
  /// clears ``items`` immediately so the view shows a loading state rather
  /// than wrong data from the previous criteria.
  public func load(_ criteria: Criteria) {
    if self.criteria != criteria {
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
    phase = .running
    task = Task { [weak self, fetch] in
      do {
        let fetched = try await fetch(criteria)
        guard !Task.isCancelled else { return }
        self?.items = fetched
        self?.lastLoaded = .now
        self?.phase = .completed
      } catch {
        guard !Task.isCancelled else { return }
        self?.phase = .failed(error.localizedDescription)
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
