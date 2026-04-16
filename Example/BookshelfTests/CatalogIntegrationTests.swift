import Foundation
import Testing
import Splint
@testable import Bookshelf

@MainActor
@Suite("Bookshelf catalog integration")
struct CatalogIntegrationTests {
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

  @Test func loadPopulatesCatalog() async {
    let client = BookClient.mock
    let catalog = Catalog<Book, BookCriteria>(fetch: client.fetchBooks)
    catalog.load(BookCriteria(libraryID: "main"))
    await waitUntil { catalog.phase == .completed }
    #expect(!catalog.items.isEmpty)
  }

  @Test func lensFiltersByGenre() async {
    let client = BookClient.mock
    let catalog = Catalog<Book, BookCriteria>(fetch: client.fetchBooks)
    catalog.load(BookCriteria(libraryID: "main"))
    await waitUntil { catalog.phase == .completed }
    let lens = Lens<Book>(source: catalog, filter: { $0.genre == "Fiction" })
    #expect(lens.items.allSatisfy { $0.genre == "Fiction" })
  }

  @Test func lensRecomputesOnRefresh() async {
    let counter = InvocationCounter()
    let client = BookClient(fetchBooks: { _ in
      let n = await counter.next()
      return [Book.sample(id: "\(n)", title: "T\(n)", genre: "G")]
    })
    let catalog = Catalog<Book, BookCriteria>(fetch: client.fetchBooks)
    catalog.load(BookCriteria(libraryID: "m"))
    await waitUntil { catalog.phase == .completed }
    let lens = Lens<Book>(source: catalog)
    await waitUntil { lens.items.first?.id == "1" }
    catalog.refresh()
    await waitUntil { lens.items.first?.id == "2" }
    #expect(lens.items.first?.id == "2")
  }

  @Test func refreshKeepsItemsVisible() async {
    let gate = MockGate()
    let counter = InvocationCounter()
    let client = BookClient(fetchBooks: { _ in
      let n = await counter.next()
      if n > 1 { await gate.wait() }
      return [Book.sample(id: "\(n)", title: "T\(n)", genre: "G")]
    })
    let catalog = Catalog<Book, BookCriteria>(fetch: client.fetchBooks)
    catalog.load(BookCriteria(libraryID: "m"))
    await waitUntil { catalog.phase == .completed }
    let first = catalog.items
    catalog.refresh()
    await waitUntil { catalog.phase == .running }
    #expect(catalog.items == first)  // items stay visible during refresh
    await gate.open()
    await waitUntil { catalog.phase == .completed && catalog.items != first }
  }
}

actor InvocationCounter {
  private var n = 0
  func next() -> Int { n += 1; return n }
}

actor MockGate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []
  func wait() async {
    if isOpen { return }
    await withCheckedContinuation { cc in waiters.append(cc) }
  }
  func open() {
    isOpen = true
    let ws = waiters; waiters.removeAll()
    for w in ws { w.resume() }
  }
}

extension Book {
  static func sample(id: String, title: String, genre: String) -> Book {
    Book(id: id, title: title, author: "A", genre: genre, year: 2020, coverURL: nil)
  }
}
