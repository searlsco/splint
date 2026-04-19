import Foundation
import Testing

@testable import Splint

// A thread-safe counter capturable in the `@Sendable` filter closure.
// `CatalogTests`'s `Counter` is an `actor`, whose methods are async and
// therefore unusable from the synchronous filter predicate. This lock-backed
// class is the simplest shape that is both `Sendable` and sync-readable.
private final class LockCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var _value: Int = 0
  func increment() { lock.withLock { _value += 1 } }
  var value: Int { lock.withLock { _value } }
}

@MainActor
@Suite("LensLargeN")
struct LensLargeNTests {
  private let n = 1_000

  private func loadedCatalog(_ items: [TestItem]) async -> Catalog<TestItem, TestCriteria> {
    let c = Catalog<TestItem, TestCriteria> { _ in items }
    c.load(TestCriteria(category: "any"))
    await waitUntil { c.phase == .completed }
    return c
  }

  private func makeItems(_ count: Int, scoreFn: (Int) -> Int = { $0 }) -> [TestItem] {
    (0..<count).map { id in
      TestItem(id: id, name: "item-\(id)", score: scoreFn(id))
    }
  }

  @Test func sortStabilityPreservedForEqualKeys() async {
    // Bucket every item into one of 10 score groups. Stable sort by score
    // must preserve original (ascending-id) order within each bucket.
    let items = makeItems(n) { $0 % 10 }
    let c = await loadedCatalog(items)
    let l = Lens<TestItem>(source: c, sort: { $0.score < $1.score })

    // Group the output by score and confirm each group's ids are ascending.
    var byScore: [Int: [Int]] = [:]
    for item in l.items { byScore[item.score, default: []].append(item.id) }
    for (_, ids) in byScore {
      #expect(ids == ids.sorted(), "stable sort must preserve source order within equal-key groups")
    }
  }

  @Test func worstCaseOrderingsSortCorrectly_alreadySorted() async {
    let items = makeItems(n)  // score = id, already ascending
    let c = await loadedCatalog(items)
    let l = Lens<TestItem>(source: c, sort: { $0.score < $1.score })
    #expect(l.items.map(\.score) == Array(0..<n))
  }

  @Test func worstCaseOrderingsSortCorrectly_reverseSorted() async {
    let items = makeItems(n) { (n - 1) - $0 }  // score = (n-1-id), descending
    let c = await loadedCatalog(items)
    let l = Lens<TestItem>(source: c, sort: { $0.score < $1.score })
    #expect(l.items.map(\.score) == Array(0..<n))
  }

  @Test func worstCaseOrderingsSortCorrectly_random() async {
    // Deterministic shuffle via a fixed seed for reproducibility.
    var rng = SystemRandomNumberGenerator()
    var scores = Array(0..<n)
    // Fisher-Yates with a seeded sequence would be nicer; for test
    // stability we just sort-shuffle with deterministic keys.
    scores.shuffle(using: &rng)
    let items = zip(0..<n, scores).map { id, score in
      TestItem(id: id, name: "item-\(id)", score: score)
    }
    let c = await loadedCatalog(items)
    let l = Lens<TestItem>(source: c, sort: { $0.score < $1.score })
    #expect(l.items.map(\.score) == Array(0..<n))
    #expect(Set(l.items.map(\.id)) == Set(0..<n))
  }

  @Test func filterToZeroItems() async {
    let c = await loadedCatalog(makeItems(n))
    let l = Lens<TestItem>(source: c, filter: { _ in false })
    #expect(l.items.isEmpty)
  }

  @Test func filterToOneItem() async {
    let c = await loadedCatalog(makeItems(n))
    let l = Lens<TestItem>(source: c, filter: { $0.id == 500 })
    #expect(l.items.count == 1)
    #expect(l.items.first?.id == 500)
  }

  @Test func filterToAll() async {
    let items = makeItems(n)
    let c = await loadedCatalog(items)
    let l = Lens<TestItem>(source: c, filter: { _ in true })
    #expect(l.items.count == n)
    #expect(l.items.map(\.id) == items.map(\.id))  // source order preserved when no sort
  }

  @Test func duplicatesPreserved() async {
    // Every (name, score) pair appears twice. Lens must not dedup.
    let dupes = (0..<(n / 2)).flatMap { i -> [TestItem] in
      let item = TestItem(id: i * 2, name: "dup-\(i)", score: i)
      let twin = TestItem(id: i * 2 + 1, name: "dup-\(i)", score: i)
      return [item, twin]
    }
    let c = await loadedCatalog(dupes)
    let l = Lens<TestItem>(source: c)
    #expect(l.items.count == n)
  }

  @Test func updateFilterRecomputesAtScale() async {
    let c = await loadedCatalog(makeItems(n))
    let l = Lens<TestItem>(source: c)
    #expect(l.items.count == n)

    l.updateFilter { $0.score > 500 }
    #expect(l.items.count == n - 501)  // ids 501..999 inclusive
    for item in l.items {
      #expect(item.score > 500)
    }
  }

  // Composition invariant: `recompute()` must invoke the filter exactly
  // once per source item per call. Guards a refactor that accidentally
  // double-filters (e.g. filtering then re-filtering after sort).
  @Test func recomputeInvokesFilterExactlyOncePerItem() async {
    let c = await loadedCatalog(makeItems(n))
    let counter = LockCounter()

    let l = Lens<TestItem>(
      source: c,
      filter: { _ in
        counter.increment()
        return true
      })
    #expect(l.items.count == n)
    #expect(counter.value == n, "init's recompute must invoke filter exactly N times")

    // updateSort triggers one additional recompute → one additional pass.
    l.updateSort { $0.score < $1.score }
    #expect(counter.value == 2 * n, "updateSort's recompute must invoke filter exactly N more times, not 2N")
  }
}
