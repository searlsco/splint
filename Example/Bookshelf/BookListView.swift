import SwiftData
import SwiftUI
import Splint

/// Lists books from the search lens. The search field updates the
/// lens's filter via `updateFilter`; each row is a child `BookRowView`
/// with its own observation scope.
public struct BookListView: View {
  @Environment(\.searchLens) private var lens
  @Environment(\.bookSelection) private var selection
  @Environment(\.showCoversSetting) private var showCovers
  @Query(sort: \Favorite.dateAdded) private var favorites: [Favorite]

  @State private var query: String = ""

  public init() {}

  public var body: some View {
    List(selection: Binding(
      get: { selection?.current },
      set: { selection?.current = $0 }
    )) {
      if let lens {
        ForEach(lens.items) { book in
          NavigationLink(value: book.id) {
            BookRowView(
              book: book,
              isFavorite: favorites.contains { $0.bookID == book.id },
              showCover: showCovers?.value ?? true
            )
          }
        }
      }
    }
    .searchable(text: $query)
    .onChange(of: query) { _, new in
      let needle = new.lowercased()
      lens?.updateFilter { book in
        needle.isEmpty
          || book.title.lowercased().contains(needle)
          || book.author.lowercased().contains(needle)
      }
    }
    .navigationTitle("Bookshelf")
  }
}
