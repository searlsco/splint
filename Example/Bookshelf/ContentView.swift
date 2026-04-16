import SwiftData
import SwiftUI
import Splint

/// The authenticated-root view. Owns every Splint instance as `@State`
/// and distributes them via `.environment()`. Lifetime of the catalog
/// and lenses is bound to this view — SwiftUI handles teardown.
public struct ContentView: View {
  private let client: BookClient

  @State private var catalog: Catalog<Book, BookCriteria>
  @State private var searchLens: Lens<Book>
  @State private var genreLens: Lens<Book>
  @State private var selection = Selection<String>()
  @State private var showCovers = Setting<Bool>("showCovers", default: true)
  @State private var preferredGenre = Setting<String>("preferredGenre", default: "All")
  @State private var path = NavigationPath()

  public init(client: BookClient) {
    self.client = client
    let c = Catalog<Book, BookCriteria>(fetch: client.fetchBooks)
    self._catalog = State(initialValue: c)
    self._searchLens = State(initialValue: Lens<Book>(source: c))
    self._genreLens = State(initialValue: Lens<Book>(source: c))
  }

  public var body: some View {
    TabView {
      NavigationStack(path: $path) {
        BookListView()
          .navigationDestination(for: String.self) { bookID in
            if let book = catalog[id: bookID] {
              BookDetailView(book: book, client: client)
            } else {
              ContentUnavailableView("Not found", systemImage: "questionmark")
            }
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
    .environment(\.searchLens, searchLens)
    .environment(\.genreLens, genreLens)
    .environment(\.bookSelection, selection)
    .environment(\.showCoversSetting, showCovers)
    .environment(\.preferredGenreSetting, preferredGenre)
    .task {
      catalog.load(BookCriteria(libraryID: "main"))
    }
    .onChange(of: preferredGenre.value) { _, new in
      genreLens.updateFilter { book in
        new == "All" || book.genre == new
      }
    }
  }
}
