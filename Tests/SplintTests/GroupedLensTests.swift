import Foundation
import Testing

@testable import Splint

// A category type whose Comparable order is deliberately NOT alphabetic,
// so tests that verify "groups are sorted by Category.<" can't pass by
// coincidence with string ordering.
private enum Priority: String, Hashable, Comparable, Sendable {
  case high, medium, low
  private var rank: Int {
    switch self {
    case .high: 0
    case .medium: 1
    case .low: 2
    }
  }
  static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rank < rhs.rank }
}

@MainActor
@Suite("GroupedLens")
struct GroupedLensTests {
  private let sample: [TestItem] = [
    TestItem(id: 1, name: "banana", score: 5),
    TestItem(id: 2, name: "apple", score: 9),
    TestItem(id: 3, name: "cherry", score: 1),
    TestItem(id: 4, name: "apricot", score: 7),
  ]

  private func loadedCatalog(_ items: [TestItem]) async -> Catalog<TestItem, TestCriteria> {
    let c = Catalog<TestItem, TestCriteria> { _ in items }
    c.load(TestCriteria(category: "any"))
    await waitUntil { c.phase == .completed }
    return c
  }

  @Test func itemsMirrorLensWhenCategorizeNil() async {
    let c = await loadedCatalog(sample)
    let l = GroupedLens<TestItem, String>(
      source: c,
      filter: { $0.score >= 5 },
      sort: { $0.score < $1.score }
    )
    #expect(l.items.map(\.score) == [5, 7, 9])
    #expect(l.groups.isEmpty)
  }

  @Test func groupsEmptyWhenCategorizeNil() async {
    let c = await loadedCatalog(sample)
    let l = GroupedLens<TestItem, String>(source: c)
    #expect(l.groups.isEmpty)
  }

  @Test func groupsPopulatedWhenCategorizeProvided() async {
    let c = await loadedCatalog(sample)
    let l = GroupedLens<TestItem, String>(
      source: c,
      categorize: { $0.name.prefix(1).lowercased() }
    )
    let keys = l.groups.map(\.category)
    #expect(keys == ["a", "b", "c"])
    #expect(l.groups.first { $0.category == "a" }?.items.map(\.id).sorted() == [2, 4])
  }

  @Test func groupsOrderedByCategoryComparable() async {
    // Priority's Comparable order is high < medium < low, NOT alphabetic.
    // Use score to assign priority so the ordering is deterministic.
    let c = await loadedCatalog(sample)
    let l = GroupedLens<TestItem, Priority>(
      source: c,
      categorize: { item in
        if item.score >= 8 { .high } else if item.score >= 5 { .medium } else { .low }
      }
    )
    #expect(l.groups.map(\.category) == [.high, .medium, .low])
  }

  @Test func groupsRespectFilter() async {
    let c = await loadedCatalog(sample)
    let l = GroupedLens<TestItem, String>(
      source: c,
      filter: { $0.score >= 5 },
      categorize: { $0.name.prefix(1).lowercased() }
    )
    // Filtered out: cherry (score 1). Remaining: banana, apple, apricot.
    let keys = l.groups.map(\.category)
    #expect(keys == ["a", "b"])  // no "c" group — cherry was filtered
    #expect(l.groups.first { $0.category == "a" }?.items.count == 2)
    #expect(l.groups.first { $0.category == "b" }?.items.count == 1)
  }

  @Test func itemsWithinGroupInheritSortOrder() async {
    let c = await loadedCatalog(sample)
    let l = GroupedLens<TestItem, String>(
      source: c,
      sort: { $0.score < $1.score },
      categorize: { $0.name.prefix(1).lowercased() }
    )
    // "a" group: apple (9), apricot (7) → sorted ascending by score.
    let a = l.groups.first { $0.category == "a" }?.items ?? []
    #expect(a.map(\.score) == [7, 9])
  }

  @Test func updateCategoriesRecomputesGroups() async {
    let c = await loadedCatalog(sample)
    let l = GroupedLens<TestItem, String>(source: c)
    #expect(l.groups.isEmpty)
    l.updateCategories { $0.name.prefix(1).lowercased() }
    #expect(l.groups.map(\.category) == ["a", "b", "c"])
  }

  @Test func updateCategoriesNilClearsGroupsPreservesItems() async {
    let c = await loadedCatalog(sample)
    let l = GroupedLens<TestItem, String>(
      source: c,
      categorize: { $0.name.prefix(1).lowercased() }
    )
    #expect(!l.groups.isEmpty)
    let itemsBefore = l.items.map(\.id)
    l.updateCategories(nil)
    #expect(l.groups.isEmpty)
    #expect(l.items.map(\.id) == itemsBefore)
  }

  @Test func updateFilterRecomputesGroups() async {
    let c = await loadedCatalog(sample)
    let l = GroupedLens<TestItem, String>(
      source: c,
      categorize: { $0.name.prefix(1).lowercased() }
    )
    #expect(l.groups.map(\.category) == ["a", "b", "c"])
    l.updateFilter { $0.name.hasPrefix("a") }
    #expect(l.groups.map(\.category) == ["a"])
  }

  @Test func updateSortRecomputesItemsWithinGroups() async {
    let c = await loadedCatalog(sample)
    let l = GroupedLens<TestItem, String>(
      source: c,
      sort: { $0.score > $1.score },  // descending
      categorize: { $0.name.prefix(1).lowercased() }
    )
    #expect(l.groups.first { $0.category == "a" }?.items.map(\.score) == [9, 7])
    l.updateSort { $0.score < $1.score }  // ascending
    #expect(l.groups.first { $0.category == "a" }?.items.map(\.score) == [7, 9])
  }

  @Test func recomputesWhenSourceRefreshes() async {
    let counter = Counter()
    let c = Catalog<TestItem, TestCriteria> { _ in
      let n = await counter.increment()
      return [TestItem(id: n, name: "x", score: n * 10)]
    }
    c.load(TestCriteria(category: "a"))
    await waitUntil { c.phase == .completed }
    let l = GroupedLens<TestItem, Int>(source: c, categorize: { $0.score })
    await waitUntil { l.items.count == 1 }
    #expect(l.groups.map(\.category) == [10])
    c.refresh()
    await waitUntil {
      if let cat = l.groups.first?.category, cat != 10 { true } else { false }
    }
    #expect(l.groups.map(\.category) == [20])
  }

  @Test func refreshReRunsCategorizerWithCurrentClosureState() async {
    let c = await loadedCatalog(sample)
    // Exogenous toggle that the categorizer reads without the lens
    // observing it — mirrors the time/locale/flag scenarios.
    let byFirstLetter = MutableBox(value: true)
    let l = GroupedLens<TestItem, String>(
      source: c,
      sort: { $0.score < $1.score },
      categorize: { item in
        byFirstLetter.value ? String(item.name.prefix(1)) : "all"
      }
    )
    #expect(Set(l.groups.map(\.category)) == Set(["b", "a", "c"]))
    byFirstLetter.value = false
    l.refresh()
    #expect(l.groups.map(\.category) == ["all"])
    #expect(l.groups.first?.items.map(\.score) == [1, 5, 7, 9])
  }

  @Test func emptySourceReturnsEmpty() async {
    let c = await loadedCatalog([])
    let l = GroupedLens<TestItem, String>(
      source: c,
      categorize: { $0.name }
    )
    #expect(l.items.isEmpty)
    #expect(l.groups.isEmpty)
  }

  @Test func reflectsSeededItemsImmediately() {
    let c = Catalog<TestItem, TestCriteria>(initialItems: sample) { _ in [] }
    let l = GroupedLens<TestItem, String>(
      source: c,
      categorize: { $0.name.prefix(1).lowercased() }
    )
    #expect(l.items.count == sample.count)
    #expect(l.groups.map(\.category) == ["a", "b", "c"])
  }

  @Test func aggregateCategorizerSeesFilteredAndSortedItems() async {
    let c = await loadedCatalog(sample)
    let seen = MutableBox<[[Int]]>(value: [])
    let l = GroupedLens<TestItem, String>(
      source: c,
      filter: { $0.score >= 5 },
      sort: { $0.score < $1.score },
      categorize: { _, all in
        seen.value.append(all.map(\.score))
        return "x"
      }
    )
    _ = l
    // One call per filtered item; each call receives the same
    // filtered+sorted collection the lens has already computed.
    #expect(seen.value.count == 3)
    #expect(seen.value.allSatisfy { $0 == [5, 7, 9] })
  }

  @Test func aggregateCategorizerBucketsRelativeToAllItems() async {
    let c = await loadedCatalog(sample)
    let l = GroupedLens<TestItem, String>(
      source: c,
      categorize: { item, all in
        let median = all.map(\.score).sorted()[all.count / 2]
        return item.score >= median ? "high" : "low"
      }
    )
    // scores: [5, 9, 1, 7] → sorted [1, 5, 7, 9]; count 4, median index 2 → 7.
    // high (>=7): apple (9), apricot (7). low: banana (5), cherry (1).
    let high = l.groups.first { $0.category == "high" }?.items.map(\.id).sorted()
    let low = l.groups.first { $0.category == "low" }?.items.map(\.id).sorted()
    #expect(high == [2, 4])
    #expect(low == [1, 3])
  }

  @Test func updateCategoriesTwoArgOverloadRecomputesGroups() async {
    let c = await loadedCatalog(sample)
    let l = GroupedLens<TestItem, String>(
      source: c,
      categorize: { $0.name.prefix(1).lowercased() }
    )
    #expect(l.groups.map(\.category) == ["a", "b", "c"])
    l.updateCategories { item, all in
      let mean = Double(all.map(\.score).reduce(0, +)) / Double(all.count)
      return Double(item.score) >= mean ? "high" : "low"
    }
    // mean = 22/4 = 5.5 → high: 9, 7; low: 5, 1
    let high = l.groups.first { $0.category == "high" }?.items.map(\.id).sorted()
    let low = l.groups.first { $0.category == "low" }?.items.map(\.id).sorted()
    #expect(high == [2, 4])
    #expect(low == [1, 3])
  }

  @Test func updateCategoriesNilClearsAfterTwoArgCategorizer() async {
    let c = await loadedCatalog(sample)
    let l = GroupedLens<TestItem, String>(
      source: c,
      categorize: { item, all in
        let mean = Double(all.map(\.score).reduce(0, +)) / Double(all.count)
        return Double(item.score) >= mean ? "high" : "low"
      }
    )
    #expect(!l.groups.isEmpty)
    l.updateCategories(nil)
    #expect(l.groups.isEmpty)
    #expect(!l.items.isEmpty)
  }

  @Test func sourceAwareCategorizerSeesRawSourceAndFilteredVisible() async {
    let c = await loadedCatalog(sample)
    let seenVisible = MutableBox<[[Int]]>(value: [])
    let seenSource = MutableBox<[[Int]]>(value: [])
    let l = GroupedLens<TestItem, String>(
      source: c,
      filter: { $0.score >= 5 },
      sort: { $0.score < $1.score },
      categorize: { _, visible, source in
        seenVisible.value.append(visible.map(\.score))
        seenSource.value.append(source.map(\.score))
        return "x"
      }
    )
    _ = l
    // One call per filtered item; visible == items (filtered+sorted),
    // source == raw catalog items (neither filtered nor sorted).
    #expect(seenVisible.value.count == 3)
    #expect(seenVisible.value.allSatisfy { $0 == [5, 7, 9] })
    #expect(seenSource.value.count == 3)
    #expect(seenSource.value.allSatisfy { $0 == [5, 9, 1, 7] })
  }

  @Test func sourceAwareBucketingStableAcrossFilter() async {
    let c = await loadedCatalog(sample)
    // Source mean = (5+9+1+7)/4 = 5.5 → high: 9, 7 ; low: 5, 1.
    let l = GroupedLens<TestItem, String>(
      source: c,
      categorize: { item, _, source in
        let mean = Double(source.map(\.score).reduce(0, +)) / Double(source.count)
        return Double(item.score) >= mean ? "high" : "low"
      }
    )
    // Baseline: full source visible.
    #expect(
      l.groups.first { $0.category == "high" }?.items.map(\.id).sorted() == [2, 4]
    )
    #expect(
      l.groups.first { $0.category == "low" }?.items.map(\.id).sorted() == [1, 3]
    )
    // Filter to just the three highest-scoring items. Buckets must
    // stay anchored to the *source* mean, so item 1 (score 5) remains
    // "low" even though it's now the lowest *visible* score.
    l.updateFilter { $0.score >= 5 }
    #expect(
      l.groups.first { $0.category == "high" }?.items.map(\.id).sorted() == [2, 4]
    )
    #expect(
      l.groups.first { $0.category == "low" }?.items.map(\.id) == [1]
    )
  }

  @Test func updateCategoriesThreeArgOverloadRecomputesGroups() async {
    let c = await loadedCatalog(sample)
    let l = GroupedLens<TestItem, String>(
      source: c,
      categorize: { $0.name.prefix(1).lowercased() }
    )
    #expect(l.groups.map(\.category) == ["a", "b", "c"])
    l.updateCategories { item, _, source in
      let mean = Double(source.map(\.score).reduce(0, +)) / Double(source.count)
      return Double(item.score) >= mean ? "high" : "low"
    }
    #expect(
      l.groups.first { $0.category == "high" }?.items.map(\.id).sorted() == [2, 4]
    )
    #expect(
      l.groups.first { $0.category == "low" }?.items.map(\.id).sorted() == [1, 3]
    )
  }

  @Test func updateCategoriesNilClearsAfterThreeArgCategorizer() async {
    let c = await loadedCatalog(sample)
    let l = GroupedLens<TestItem, String>(
      source: c,
      categorize: { item, _, source in
        let mean = Double(source.map(\.score).reduce(0, +)) / Double(source.count)
        return Double(item.score) >= mean ? "high" : "low"
      }
    )
    #expect(!l.groups.isEmpty)
    l.updateCategories(nil)
    #expect(l.groups.isEmpty)
    #expect(!l.items.isEmpty)
  }

  @Test func clearsWhenSourceClearsOnCriteriaChange() async {
    let counter = Counter()
    let c = Catalog<TestItem, TestCriteria> { _ in
      let n = await counter.increment()
      if n == 1 { return [TestItem(id: 1, name: "a", score: 1)] }
      try? await Task.sleep(for: .milliseconds(200))
      return [TestItem(id: 2, name: "b", score: 2)]
    }
    c.load(TestCriteria(category: "a"))
    await waitUntil { c.phase == .completed }
    let l = GroupedLens<TestItem, String>(
      source: c,
      categorize: { $0.name }
    )
    await waitUntil { l.items.count == 1 }
    #expect(!l.groups.isEmpty)
    c.load(TestCriteria(category: "b"))
    await waitUntil { l.items.isEmpty }
    #expect(l.items.isEmpty)
    #expect(l.groups.isEmpty)
  }
}
