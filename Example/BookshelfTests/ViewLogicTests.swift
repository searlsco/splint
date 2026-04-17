import Foundation
import Testing
import Splint
@testable import Bookshelf

@MainActor
@Suite("Bookshelf view-logic composition")
struct ViewLogicTests {
  private func book(_ id: String, genre: String) -> Book {
    Book(id: id, title: "T\(id)", author: "A", genre: genre, year: 2020)
  }

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

  // MARK: - visibleBooks intersection

  @Test func intersectionKeepsOnlyBooksInBothLenses() {
    let f = book("f", genre: "Fiction")
    let n = book("n", genre: "Nonfiction")
    #expect(
      BookListView.intersection(search: [f, n], genre: [f]).map(\.id) == ["f"]
    )
  }

  @Test func intersectionWhenGenreLensIsEmpty() {
    let a = book("a", genre: "X")
    #expect(BookListView.intersection(search: [a], genre: []).isEmpty)
  }

  @Test func intersectionWhenSearchLensIsEmpty() {
    let a = book("a", genre: "X")
    #expect(BookListView.intersection(search: [], genre: [a]).isEmpty)
  }

  @Test func intersectionWhenBothLensesAreEmpty() {
    #expect(BookListView.intersection(search: [], genre: []).isEmpty)
  }

  @Test func intersectionPreservesSearchLensOrder() {
    let a = book("a", genre: "X")
    let b = book("b", genre: "X")
    let c = book("c", genre: "X")
    let result = BookListView.intersection(search: [c, a, b], genre: [a, b, c])
    #expect(result.map(\.id) == ["c", "a", "b"])
  }

  // MARK: - genres clamp

  @Test func genresIncludesPersistedValueWhenCatalogIsEmpty() {
    #expect(
      SettingsView.buildGenres(catalogItems: [], persisted: "Sci-Fi") == ["All", "Sci-Fi"]
    )
  }

  @Test func genresIsJustAllWhenNothingPersistedAndCatalogEmpty() {
    #expect(SettingsView.buildGenres(catalogItems: [], persisted: nil) == ["All"])
  }

  @Test func genresMergesCatalogGenresAndPersistedValue() {
    let books = [book("1", genre: "Fiction"), book("2", genre: "Nonfiction")]
    #expect(
      SettingsView.buildGenres(catalogItems: books, persisted: "Sci-Fi")
        == ["All", "Fiction", "Nonfiction", "Sci-Fi"]
    )
  }

  @Test func genresDedupesPersistedValueAlreadyInCatalog() {
    let books = [book("1", genre: "Fiction")]
    #expect(
      SettingsView.buildGenres(catalogItems: books, persisted: "Fiction")
        == ["All", "Fiction"]
    )
  }

  @Test func genresDoesNotDuplicateAllEvenIfCatalogContainsAll() {
    let books = [book("1", genre: "All")]
    #expect(
      SettingsView.buildGenres(catalogItems: books, persisted: "All") == ["All"]
    )
  }

  // MARK: - Setting→Lens seeding (proxy for .onChange(initial: true))

  @Test func persistedPreferredGenreNarrowsLensOnFirstApply() async {
    // Isolate UserDefaults per test to avoid cross-test contamination.
    let suite = "BookshelfTests.ViewLogicTests.\(UUID().uuidString)"
    let store = UserDefaults(suiteName: suite)!
    defer { store.removePersistentDomain(forName: suite) }
    store.set("Fiction", forKey: "preferredGenre")

    // Simulate what ContentView does with `.onChange(initial: true)`:
    // read the Setting's current value (now "Fiction" from UserDefaults)
    // and apply it to the lens as the initial filter.
    let setting = Setting<String>("preferredGenre", default: "All", store: store)
    #expect(setting.value == "Fiction")

    let catalog = Catalog<Book, BookCriteria>(fetch: BookClient.mock.fetchBooks)
    catalog.load(BookCriteria(libraryID: "main"))
    await waitUntil { catalog.phase == .completed }

    let lens = Lens<Book>(source: catalog)
    let current = setting.value
    lens.updateFilter { book in current == "All" || book.genre == current }

    #expect(!lens.items.isEmpty)
    #expect(lens.items.allSatisfy { $0.genre == "Fiction" })
  }

  @Test func allSentinelShowsEveryBookThroughLensFilter() async {
    let suite = "BookshelfTests.ViewLogicTests.\(UUID().uuidString)"
    let store = UserDefaults(suiteName: suite)!
    defer { store.removePersistentDomain(forName: suite) }
    // No value set → Setting falls back to default "All".
    let setting = Setting<String>("preferredGenre", default: "All", store: store)
    #expect(setting.value == "All")

    let catalog = Catalog<Book, BookCriteria>(fetch: BookClient.mock.fetchBooks)
    catalog.load(BookCriteria(libraryID: "main"))
    await waitUntil { catalog.phase == .completed }

    let lens = Lens<Book>(source: catalog)
    let current = setting.value
    lens.updateFilter { book in current == "All" || book.genre == current }

    #expect(lens.items.count == catalog.items.count)
  }
}
