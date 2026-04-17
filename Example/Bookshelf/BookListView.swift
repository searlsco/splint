import SwiftData
import SwiftUI
import Splint

/// Lists books at the intersection of two lenses on the same catalog —
/// `searchLens` (title/author substring) and `genreLens` (preferred
/// genre). The combination of `List(selection:)` + `NavigationLink(value:)`
/// is Apple's canonical NavigationSplitView pattern: selection drives the
/// detail column on regular widths, NavigationLink provides the push +
/// chevron affordance on iPhone compact.
public struct BookListView: View {
  @Environment(\.bookCatalog) private var catalog
  @Environment(\.searchLens) private var searchLens
  @Environment(\.genreLens) private var genreLens
  @Environment(\.bookSelection) private var selection
  @Environment(\.showCoversSetting) private var showCovers
  @Query(sort: \Favorite.dateAdded) private var favorites: [Favorite]

  @State private var query: String = ""

  public init() {}

  private var visibleBooks: [Book] {
    guard let searchLens, let genreLens else { return [] }
    return Self.intersection(search: searchLens.items, genre: genreLens.items)
  }

  /// Intersection of two lens projections by `id`. Extracted for
  /// testability — exercises the `Set`-based O(n) lookup and the
  /// boundary cases (either lens empty).
  static func intersection(search: [Book], genre: [Book]) -> [Book] {
    let genreIDs = Set(genre.map(\.id))
    return search.filter { genreIDs.contains($0.id) }
  }

  public var body: some View {
    List(selection: Binding(
      get: { selection?.current },
      set: { selection?.current = $0 }
    )) {
      ForEach(visibleBooks) { book in
        NavigationLink(value: book.id) {
          BookRowView(
            book: book,
            isFavorite: favorites.contains { $0.bookID == book.id },
            showCover: showCovers?.value ?? true
          )
        }
      }
    }
    .overlay {
      if visibleBooks.isEmpty {
        switch catalog?.phase {
        case .idle, .running, nil:
          ProgressView("Loading books…")
        case .completed:
          ContentUnavailableView(
            "No Books",
            systemImage: "books.vertical",
            description: Text("Try a different search or genre.")
          )
        case .failed(let message):
          ContentUnavailableView(
            "Couldn't load books",
            systemImage: "exclamationmark.triangle",
            description: Text(message)
          )
        }
      }
    }
    .searchable(text: $query)
    .onChange(of: query) { _, new in
      let needle = new.lowercased()
      searchLens?.updateFilter { book in
        needle.isEmpty
          || book.title.lowercased().contains(needle)
          || book.author.lowercased().contains(needle)
      }
    }
    .navigationTitle("Bookshelf")
  }
}
