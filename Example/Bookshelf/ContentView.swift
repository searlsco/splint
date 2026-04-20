import SwiftData
import SwiftUI
import Splint

/// The authenticated-root view. Owns every Splint instance as `@State`
/// and distributes them via `.environment()`. Lifetime of the catalog
/// and lens is bound to this view — SwiftUI handles teardown.
public struct ContentView: View {
  private let client: BookClient

  @State private var catalog: Catalog<Book, BookCriteria>
  @State private var displayLens: GroupedLens<Book, String>
  @State private var selection = Selection<String>()
  @State private var showCovers = Setting<Bool>("showCovers", default: true)
  @State private var preferredGenre = Setting<String>("preferredGenre", default: "All")
  @State private var query: String = ""
  @State private var apiCredentialStatus = CredentialStatus(
    credential: Credential(
      service: bookshelfCredentialService,
      account: bookshelfCredentialAccount,
      synchronizable: false
    )
  )

  public init(client: BookClient) {
    self.client = client
    // Seed the catalog with a tiny cached snapshot so the list renders
    // immediately on cold launch instead of flashing empty while the
    // async `fetchBooks` runs. Real apps would read this from a disk
    // cache keyed by the last successful fetch; for the example a
    // handful of hardcoded entries suffices to demonstrate the seam.
    let cached: [Book] = [
      Book(id: "seed-1", title: "Cached: Dune", author: "Frank Herbert", genre: "Fiction", year: 1965),
      Book(id: "seed-2", title: "Cached: Foundation", author: "Isaac Asimov", genre: "Fiction", year: 1951),
      Book(id: "seed-3", title: "Cached: Neuromancer", author: "William Gibson", genre: "Fiction", year: 1984),
    ]
    let c = Catalog<Book, BookCriteria>(initialItems: cached, fetch: client.fetchBooks)
    self._catalog = State(initialValue: c)
    self._displayLens = State(initialValue: GroupedLens<Book, String>(source: c))
  }

  public var body: some View {
    TabView {
      NavigationSplitView {
        BookListView(query: $query)
      } detail: {
        if let id = selection.current, let book = catalog[id: id] {
          BookDetailView(book: book, client: client)
        } else {
          ContentUnavailableView("Pick a book", systemImage: "books.vertical")
        }
      }
      .tabItem { Label("Books", systemImage: "books.vertical") }

      NavigationStack {
        FavoritesView()
      }
      .tabItem { Label("Favorites", systemImage: "heart") }

      NavigationStack {
        SettingsView()
      }
      .tabItem { Label("Settings", systemImage: "gear") }
    }
    .environment(\.bookCatalog, catalog)
    .environment(\.displayLens, displayLens)
    .environment(\.bookSelection, selection)
    .environment(\.showCoversSetting, showCovers)
    .environment(\.preferredGenreSetting, preferredGenre)
    .environment(\.apiCredentialStatus, apiCredentialStatus)
    .task {
      apiCredentialStatus.refresh()
      catalog.load(BookCriteria(libraryID: "main"))
    }
    // `initial: true` is load-bearing: `Setting` reads from UserDefaults
    // at init, so on any relaunch after the user picked a non-"All"
    // genre the Picker reads e.g. "Fiction" but the lens still has its
    // default all-true filter. Firing onChange once on appear seeds
    // the lens from the persisted Setting.
    .onChange(of: query, initial: true) { _, _ in applyFilter() }
    .onChange(of: preferredGenre.value, initial: true) { _, _ in applyFilter() }
  }

  private func applyFilter() {
    let needle = query.lowercased()
    let genre = preferredGenre.value
    displayLens.updateFilter { book in
      let genreOK = genre == "All" || book.genre == genre
      let searchOK =
        needle.isEmpty
        || book.title.lowercased().contains(needle)
        || book.author.lowercased().contains(needle)
      return genreOK && searchOK
    }
  }
}
