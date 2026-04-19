import Foundation
import Testing
import Splint
@testable import Bookshelf

@MainActor
@Suite("Bookshelf view-logic composition")
struct ViewLogicTests {
  private func book(_ id: String, title: String = "T", author: String = "A", genre: String) -> Book {
    Book(id: id, title: title, author: author, genre: genre, year: 2020)
  }

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

  // MARK: - displayLens: combined search + genre filter

  @Test func displayLensFiltersBySearchAndGenreTogether() async {
    let books = [
      book("1", title: "Pragmatic Programmer", genre: "Nonfiction"),
      book("2", title: "Annihilation", genre: "Fiction"),
      book("3", title: "Authority", genre: "Fiction"),
    ]
    let catalog = Catalog<Book, BookCriteria> { _ in books }
    catalog.load(BookCriteria(libraryID: "main"))
    await waitUntil { catalog.phase == .completed }
    let lens = GroupedLens<Book, String>(source: catalog)

    // Composite filter matches what ContentView.applyFilter installs.
    lens.updateFilter { b in
      b.genre == "Fiction" && b.title.lowercased().contains("author")
    }

    #expect(lens.items.map(\.id) == ["3"])
  }

  // MARK: - grouping via displayLens

  @Test func groupingByAuthorProducesOneGroupPerDistinctAuthor() async {
    let books = [
      book("1", author: "Lopez", genre: "X"),
      book("2", author: "Carr", genre: "X"),
      book("3", author: "Lopez", genre: "X"),
      book("4", author: "Abrams", genre: "X"),
    ]
    let catalog = Catalog<Book, BookCriteria> { _ in books }
    catalog.load(BookCriteria(libraryID: "main"))
    await waitUntil { catalog.phase == .completed }
    let lens = GroupedLens<Book, String>(
      source: catalog,
      categorize: { $0.author }
    )
    #expect(lens.groups.map(\.category) == ["Abrams", "Carr", "Lopez"])
    #expect(lens.groups.first { $0.category == "Lopez" }?.items.count == 2)
  }

  @Test func groupingByGenreProducesOneGroupPerDistinctGenre() async {
    let books = [
      book("1", author: "A", genre: "Fiction"),
      book("2", author: "B", genre: "Nonfiction"),
      book("3", author: "C", genre: "Fiction"),
      book("4", author: "D", genre: "Biography"),
    ]
    let catalog = Catalog<Book, BookCriteria> { _ in books }
    catalog.load(BookCriteria(libraryID: "main"))
    await waitUntil { catalog.phase == .completed }
    let lens = GroupedLens<Book, String>(
      source: catalog,
      categorize: { $0.genre }
    )
    #expect(lens.groups.map(\.category) == ["Biography", "Fiction", "Nonfiction"])
    #expect(lens.groups.first { $0.category == "Fiction" }?.items.map(\.id).sorted() == ["1", "3"])
    #expect(lens.groups.first { $0.category == "Biography" }?.items.map(\.id) == ["4"])
  }

  @Test func groupingNoneLeavesGroupsEmpty() async {
    let books = [book("1", genre: "X")]
    let catalog = Catalog<Book, BookCriteria> { _ in books }
    catalog.load(BookCriteria(libraryID: "main"))
    await waitUntil { catalog.phase == .completed }
    let lens = GroupedLens<Book, String>(source: catalog)
    #expect(lens.groups.isEmpty)
    #expect(lens.items.count == 1)
  }

  @Test func togglingGroupingKeepsItemsStable() async {
    let books = [
      book("1", author: "A", genre: "X"),
      book("2", author: "B", genre: "Y"),
    ]
    let catalog = Catalog<Book, BookCriteria> { _ in books }
    catalog.load(BookCriteria(libraryID: "main"))
    await waitUntil { catalog.phase == .completed }
    let lens = GroupedLens<Book, String>(source: catalog)
    let idsBeforeGrouping = lens.items.map(\.id)

    lens.updateCategories { $0.author }
    #expect(!lens.groups.isEmpty)
    #expect(lens.items.map(\.id) == idsBeforeGrouping)

    lens.updateCategories(nil)
    #expect(lens.groups.isEmpty)
    #expect(lens.items.map(\.id) == idsBeforeGrouping)
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

    let setting = Setting<String>("preferredGenre", default: "All", store: store)
    #expect(setting.value == "Fiction")

    let catalog = Catalog<Book, BookCriteria>(fetch: BookClient.mock.fetchBooks)
    catalog.load(BookCriteria(libraryID: "main"))
    await waitUntil { catalog.phase == .completed }

    let lens = GroupedLens<Book, String>(source: catalog)
    let current = setting.value
    lens.updateFilter { book in current == "All" || book.genre == current }

    #expect(!lens.items.isEmpty)
    #expect(lens.items.allSatisfy { $0.genre == "Fiction" })
  }

  @Test func allSentinelShowsEveryBookThroughLensFilter() async {
    let suite = "BookshelfTests.ViewLogicTests.\(UUID().uuidString)"
    let store = UserDefaults(suiteName: suite)!
    defer { store.removePersistentDomain(forName: suite) }
    let setting = Setting<String>("preferredGenre", default: "All", store: store)
    #expect(setting.value == "All")

    let catalog = Catalog<Book, BookCriteria>(fetch: BookClient.mock.fetchBooks)
    catalog.load(BookCriteria(libraryID: "main"))
    await waitUntil { catalog.phase == .completed }

    let lens = GroupedLens<Book, String>(source: catalog)
    let current = setting.value
    lens.updateFilter { book in current == "All" || book.genre == current }

    #expect(lens.items.count == catalog.items.count)
  }
}
