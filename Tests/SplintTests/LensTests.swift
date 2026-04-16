import Foundation
import Testing

@testable import Splint

@MainActor
@Suite("Lens")
struct LensTests {
  private func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: () -> Bool
  ) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
      if condition() { return }
      try? await Task.sleep(for: .milliseconds(5))
    }
  }

  private let sample: [TestItem] = [
    TestItem(id: 1, name: "banana", score: 5),
    TestItem(id: 2, name: "apple", score: 9),
    TestItem(id: 3, name: "cherry", score: 1),
  ]

  private func loadedCatalog(_ items: [TestItem]) async -> Catalog<TestItem, TestCriteria> {
    let c = Catalog<TestItem, TestCriteria> { _ in items }
    c.load(TestCriteria(category: "any"))
    await waitUntil { c.phase == .completed }
    return c
  }

  @Test func filtersItemsFromSource() async {
    let c = await loadedCatalog(sample)
    let l = Lens<TestItem>(source: c, filter: { $0.score >= 5 })
    #expect(Set(l.items.map(\.id)) == Set([1, 2]))
  }

  @Test func sortsItemsFromSource() async {
    let c = await loadedCatalog(sample)
    let l = Lens<TestItem>(source: c, sort: { $0.score < $1.score })
    #expect(l.items.map(\.score) == [1, 5, 9])
  }

  @Test func recomputesWhenSourceRefreshes() async {
    let counter = Counter()
    let c = Catalog<TestItem, TestCriteria> { _ in
      let n = await counter.increment()
      return [TestItem(id: n, name: "x", score: n * 10)]
    }
    c.load(TestCriteria(category: "a"))
    await waitUntil { c.phase == .completed }
    let l = Lens<TestItem>(source: c)
    await waitUntil { l.items.count == 1 }
    #expect(l.items.first?.score == 10)
    c.refresh()
    await waitUntil {
      if let s = l.items.first?.score, s != 10 { true } else { false }
    }
    #expect(l.items.first?.score == 20)
  }

  @Test func filterAndSortTogether() async {
    let c = await loadedCatalog(sample)
    let l = Lens<TestItem>(
      source: c,
      filter: { $0.score >= 5 },
      sort: { $0.score > $1.score }
    )
    #expect(l.items.map(\.score) == [9, 5])
  }

  @Test func updateFilterChangesAndRecomputes() async {
    let c = await loadedCatalog(sample)
    let l = Lens<TestItem>(source: c)
    #expect(l.items.count == 3)
    l.updateFilter { $0.name == "apple" }
    #expect(l.items.map(\.name) == ["apple"])
  }

  @Test func updateSortChangesAndRecomputes() async {
    let c = await loadedCatalog(sample)
    let l = Lens<TestItem>(source: c)
    l.updateSort { $0.score < $1.score }
    #expect(l.items.map(\.score) == [1, 5, 9])
  }

  @Test func updateSortNilReturnsSourceOrder() async {
    let c = await loadedCatalog(sample)
    let l = Lens<TestItem>(source: c, sort: { $0.score < $1.score })
    #expect(l.items.map(\.id) == [3, 1, 2])
    l.updateSort(nil)
    #expect(l.items.map(\.id) == [1, 2, 3])
  }

  @Test func defaultParamsReturnsAllInSourceOrder() async {
    let c = await loadedCatalog(sample)
    let l = Lens<TestItem>(source: c)
    #expect(l.items.map(\.id) == [1, 2, 3])
  }

  @Test func emptySourceReturnsEmpty() async {
    let c = await loadedCatalog([])
    let l = Lens<TestItem>(source: c)
    #expect(l.items.isEmpty)
  }

  @Test func clearsWhenSourceClearsOnCriteriaChange() async {
    // First load populates.
    let counter = Counter()
    let c = Catalog<TestItem, TestCriteria> { _ in
      let n = await counter.increment()
      if n == 1 { return [TestItem(id: 1, name: "a", score: 1)] }
      // Block the 2nd fetch so the lens observes the intermediate empty
      // state after the criteria-change clear.
      try? await Task.sleep(for: .milliseconds(200))
      return [TestItem(id: 2, name: "b", score: 2)]
    }
    c.load(TestCriteria(category: "a"))
    await waitUntil { c.phase == .completed }
    let l = Lens<TestItem>(source: c)
    await waitUntil { l.items.count == 1 }
    c.load(TestCriteria(category: "b"))
    await waitUntil { l.items.isEmpty }
    #expect(l.items.isEmpty)
  }
}
