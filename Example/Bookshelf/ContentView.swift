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
  @State private var apiCredentialStatus = CredentialStatus(
    credential: Credential(
      service: bookshelfCredentialService,
      account: bookshelfCredentialAccount,
      synchronizable: false
    )
  )

  public init(client: BookClient) {
    self.client = client
    let c = Catalog<Book, BookCriteria>(fetch: client.fetchBooks)
    self._catalog = State(initialValue: c)
    self._searchLens = State(initialValue: Lens<Book>(source: c))
    self._genreLens = State(initialValue: Lens<Book>(source: c))
  }

  public var body: some View {
    TabView {
      NavigationSplitView {
        BookListView()
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
    .environment(\.searchLens, searchLens)
    .environment(\.genreLens, genreLens)
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
    // genre the Picker reads e.g. "Fiction" but `genreLens` still has
    // its default all-true filter. Firing onChange once on appear
    // seeds the lens from the persisted Setting.
    .onChange(of: preferredGenre.value, initial: true) { _, new in
      genreLens.updateFilter { book in
        new == "All" || book.genre == new
      }
    }
  }
}
