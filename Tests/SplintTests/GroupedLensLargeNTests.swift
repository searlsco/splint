import Foundation
import Testing

@testable import Splint

// Shared with LensLargeNTests; duplicated here until a third site earns
// the extraction.
private final class LockCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var _value: Int = 0
  func increment() { lock.withLock { _value += 1 } }
  var value: Int { lock.withLock { _value } }
}

@MainActor
@Suite("GroupedLensLargeN")
struct GroupedLensLargeNTests {
  private let n = 1_000

  private func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: () -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
      if condition() { return }
      try? await Task.sleep(for: .milliseconds(5))
    }
    #expect(condition(), "waitUntil timed out after \(timeout)", sourceLocation: sourceLocation)
  }

  private func loadedCatalog(_ items: [TestItem]) async -> Catalog<TestItem, TestCriteria> {
    let c = Catalog<TestItem, TestCriteria> { _ in items }
    c.load(TestCriteria(category: "any"))
    await waitUntil { c.phase == .completed }
    return c
  }

  private func makeItems(_ count: Int) -> [TestItem] {
    (0..<count).map { id in
      TestItem(id: id, name: "item-\(id)", score: id)
    }
  }

  @Test func groupsCorrectlyAtScale() async {
    let c = await loadedCatalog(makeItems(n))
    let l = GroupedLens<TestItem, Int>(
      source: c,
      categorize: { $0.score % 10 }
    )
    #expect(l.groups.count == 10)
    #expect(l.groups.map(\.category) == Array(0..<10))
    for (i, group) in l.groups.enumerated() {
      #expect(group.items.count == n / 10, "bucket \(i) size")
      #expect(group.items.allSatisfy { $0.score % 10 == i })
    }
  }

  // Composition invariants: `recompute()` must invoke the categorizer
  // exactly once per item that passes the filter, per call. Guards a
  // refactor that accidentally double-categorizes. Split by trigger so
  // a failure identifies *which* recompute over-categorized.

  @Test func initRecomputeInvokesCategorizeOncePerFilteredItem() async {
    let c = await loadedCatalog(makeItems(n))
    let counter = LockCounter()

    let l = GroupedLens<TestItem, Int>(
      source: c,
      filter: { $0.score >= 500 },  // passes ids 500..999 → 500 items
      categorize: { item in
        counter.increment()
        return item.score % 10
      }
    )
    _ = l  // keep observation alive
    #expect(counter.value == 500, "init's recompute must invoke categorize exactly once per filtered item")
  }

  @Test func updateSortRecomputeInvokesCategorizeOncePerFilteredItem() async {
    let c = await loadedCatalog(makeItems(n))
    let counter = LockCounter()

    let l = GroupedLens<TestItem, Int>(
      source: c,
      filter: { $0.score >= 500 },
      categorize: { item in
        counter.increment()
        return item.score % 10
      }
    )
    let afterInit = counter.value
    l.updateSort { $0.score < $1.score }
    #expect(counter.value - afterInit == 500, "updateSort's recompute must invoke categorize exactly once per filtered item, not 2×")
  }

  @Test func groupingDoesNotDegradeSortStability() async {
    // Within a group, items should appear in the lens's sort order.
    // Here: ascending by id (the default when no sort, since Catalog
    // preserves source order and we build items in id-order).
    let c = await loadedCatalog(makeItems(n))
    let l = GroupedLens<TestItem, Int>(
      source: c,
      categorize: { $0.score % 10 }
    )
    for group in l.groups {
      let ids = group.items.map(\.id)
      #expect(ids == ids.sorted(), "group \(group.category): items must preserve source order")
    }
  }
}
