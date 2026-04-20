import Foundation
import Testing

@_spi(Internal) @testable import Splint

struct TestItem: Resource {
  let id: Int
  let name: String
  let score: Int
}

struct TestCriteria: Equatable, Sendable {
  let category: String
}

private struct Boom: Error, LocalizedError {
  let msg: String
  var errorDescription: String? { msg }
}

@MainActor
@Suite("Catalog")
struct CatalogTests {
  private func makeCatalog(
    items: [TestItem] = [
      TestItem(id: 1, name: "A", score: 10),
      TestItem(id: 2, name: "B", score: 20),
    ]
  ) -> Catalog<TestItem, TestCriteria> {
    Catalog<TestItem, TestCriteria> { _ in items }
  }

  @Test func loadPopulatesItemsAndSetsCriteria() async {
    let c = makeCatalog()
    c.load(TestCriteria(category: "x"))
    await waitUntil { c.phase == .completed }
    #expect(c.items.count == 2)
    #expect(c.criteria == TestCriteria(category: "x"))
  }

  @Test func phaseTransitionsIdleRunningCompleted() async {
    let gate = AsyncGate()
    let c = Catalog<TestItem, TestCriteria> { _ in
      await gate.wait()
      return [TestItem(id: 1, name: "A", score: 1)]
    }
    #expect(c.phase == .idle)
    c.load(TestCriteria(category: "x"))
    await waitUntil { c.phase == .running }
    #expect(c.phase == .running)
    await gate.open()
    await waitUntil { c.phase == .completed }
    #expect(c.phase == .completed)
  }

  @Test func lastLoadedSetOnCompletion() async {
    let c = makeCatalog()
    #expect(c.lastLoaded == nil)
    c.load(TestCriteria(category: "x"))
    await waitUntil { c.phase == .completed }
    #expect(c.lastLoaded != nil)
  }

  @Test func failedFetchSetsFailedPhase() async {
    let c = Catalog<TestItem, TestCriteria> { _ in throw Boom(msg: "nope") }
    c.load(TestCriteria(category: "x"))
    await waitUntil {
      if case .failed = c.phase { true } else { false }
    }
    #expect(c.phase == .failed("nope"))
    #expect(c.items.isEmpty)
  }

  @Test func loadSameCriteriaKeepsItemsVisibleDuringFetch() async {
    let gate = AsyncGate()
    let initial = [TestItem(id: 1, name: "A", score: 1)]
    let refreshed = [TestItem(id: 2, name: "B", score: 2)]
    let counter = Counter()
    let c = Catalog<TestItem, TestCriteria> { _ in
      let n = await counter.increment()
      if n > 1 { await gate.wait() }
      return n == 1 ? initial : refreshed
    }
    let crit = TestCriteria(category: "x")
    c.load(crit)
    await waitUntil { c.phase == .completed && c.items == initial }
    c.load(crit)
    await waitUntil { c.phase == .running }
    // Same criteria: items remain visible while the new fetch runs.
    #expect(c.items == initial)
    await gate.open()
    await waitUntil { c.items == refreshed }
  }

  @Test func loadDifferentCriteriaClearsItemsImmediately() async {
    let gate = AsyncGate()
    let counter = Counter()
    let c = Catalog<TestItem, TestCriteria> { _ in
      let n = await counter.increment()
      if n > 1 { await gate.wait() }
      return [TestItem(id: n, name: "X", score: n)]
    }
    c.load(TestCriteria(category: "a"))
    await waitUntil { c.phase == .completed }
    #expect(!c.items.isEmpty)
    c.load(TestCriteria(category: "b"))
    // Clearing is synchronous on the load() call itself.
    #expect(c.items.isEmpty)
    await gate.open()
    await waitUntil { c.phase == .completed && !c.items.isEmpty }
  }

  @Test func refreshReusesCurrentCriteria() async {
    let counter = Counter()
    let c = Catalog<TestItem, TestCriteria> { _ in
      let n = await counter.increment()
      return [TestItem(id: n, name: "X", score: n)]
    }
    c.load(TestCriteria(category: "a"))
    await waitUntil { c.phase == .completed }
    let firstCount = c.items.first?.score
    c.refresh()
    await waitUntil {
      if let s = c.items.first?.score, s != firstCount { true } else { false }
    }
    #expect(c.criteria == TestCriteria(category: "a"))
    #expect(c.items.first?.score != firstCount)
  }

  @Test func refreshIsNoopWhenLoadNeverCalled() async {
    let called = Counter()
    let c = Catalog<TestItem, TestCriteria> { _ in
      _ = await called.increment()
      return []
    }
    c.refresh()
    // Allow a moment — nothing should happen.
    try? await Task.sleep(for: .milliseconds(50))
    #expect(c.phase == .idle)
    #expect(await called.value == 0)
  }

  @Test func retryBehavesLikeRefresh() async {
    let counter = Counter()
    let c = Catalog<TestItem, TestCriteria> { _ in
      let n = await counter.increment()
      if n == 1 { throw Boom(msg: "first") }
      return [TestItem(id: 9, name: "Z", score: 9)]
    }
    c.load(TestCriteria(category: "a"))
    await waitUntil {
      if case .failed = c.phase { true } else { false }
    }
    c.retry()
    await waitUntil { c.phase == .completed }
    #expect(c.items.first?.id == 9)
  }

  @Test func loadWhileRunningCancelsPrevious() async {
    let gate = AsyncGate()
    let counter = Counter()
    let c = Catalog<TestItem, TestCriteria> { crit in
      let n = await counter.increment()
      if n == 1 {
        await gate.wait()
        return [TestItem(id: 99, name: "stale", score: 0)]
      }
      return [TestItem(id: Int(crit.category) ?? 0, name: crit.category, score: 1)]
    }
    c.load(TestCriteria(category: "1"))
    await waitUntil { c.phase == .running }
    let task1 = c.currentTask
    c.load(TestCriteria(category: "2"))
    await c.currentTask?.value
    #expect(c.items.first?.name == "2")
    // Let the first (superseded) task wake up — it must NOT overwrite items.
    await gate.open()
    await task1?.value
    #expect(c.items.first?.name == "2")
  }

  @Test func subscriptReturnsMatchingItem() async {
    let c = makeCatalog()
    c.load(TestCriteria(category: "x"))
    await waitUntil { c.phase == .completed }
    #expect(c[id: 1]?.name == "A")
    #expect(c[id: 99] == nil)
  }

  @Test func initialItemsSeedsItemsBeforeAnyLoad() {
    let seed = [TestItem(id: 1, name: "seed", score: 0)]
    let c = Catalog<TestItem, TestCriteria>(initialItems: seed) { _ in [] }
    #expect(c.items == seed)
    #expect(c.phase == .idle)
    #expect(c.criteria == nil)
    #expect(c.lastLoaded == nil)
  }

  @Test func firstLoadPreservesSeededItemsUntilFetchCompletes() async {
    let gate = AsyncGate()
    let seed = [TestItem(id: 1, name: "seed", score: 0)]
    let fresh = [TestItem(id: 2, name: "fresh", score: 1)]
    let c = Catalog<TestItem, TestCriteria>(initialItems: seed) { _ in
      await gate.wait()
      return fresh
    }
    c.load(TestCriteria(category: "x"))
    await waitUntil { c.phase == .running }
    // Seed is still visible while fetch is in flight.
    #expect(c.items == seed)
    await gate.open()
    await waitUntil { c.items == fresh }
  }

  @Test func seededCatalogClearsWhenSwitchingBetweenNonNilCriteria() async {
    let gate = AsyncGate()
    let counter = Counter()
    let seed = [TestItem(id: 0, name: "seed", score: 0)]
    let c = Catalog<TestItem, TestCriteria>(initialItems: seed) { _ in
      let n = await counter.increment()
      if n > 1 { await gate.wait() }
      return [TestItem(id: n, name: "fetched", score: n)]
    }
    c.load(TestCriteria(category: "a"))
    await waitUntil { c.phase == .completed }
    #expect(c.items.first?.name == "fetched")
    c.load(TestCriteria(category: "b"))
    // Clearing is synchronous when switching between distinct non-nil criteria.
    #expect(c.items.isEmpty)
    await gate.open()
    await waitUntil { c.phase == .completed && !c.items.isEmpty }
  }

  @Test func noCriteriaConvenienceWorksWithoutArgs() async {
    let c = Catalog<TestItem, NoCriteria> {
      [TestItem(id: 1, name: "A", score: 1)]
    }
    c.load()
    await waitUntil { c.phase == .completed }
    #expect(c.items.count == 1)
  }
}

// MARK: - Test helpers

actor Counter {
  private var _value: Int = 0
  var value: Int { _value }
  func increment() -> Int {
    _value += 1
    return _value
  }
}

actor AsyncGate {
  private var isOpen: Bool = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    if isOpen { return }
    await withCheckedContinuation { cc in
      waiters.append(cc)
    }
  }

  func open() {
    isOpen = true
    let ws = waiters
    waiters.removeAll()
    for w in ws { w.resume() }
  }
}
