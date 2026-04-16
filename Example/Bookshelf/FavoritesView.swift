import SwiftData
import SwiftUI
import Splint

/// Demonstrates SwiftData + Catalog interop: `@Query` fetches the
/// persistent favorites; `catalog[id:]` joins them to the current Book.
public struct FavoritesView: View {
  @Environment(\.bookCatalog) private var catalog
  @Query(sort: \Favorite.dateAdded, order: .reverse) private var favorites: [Favorite]

  public init() {}

  public var body: some View {
    List {
      ForEach(favorites) { fav in
        FavoriteRow(favorite: fav, book: catalog?[id: fav.bookID])
      }
    }
    .navigationTitle("Favorites")
    .overlay {
      if favorites.isEmpty {
        ContentUnavailableView(
          "No Favorites Yet",
          systemImage: "heart",
          description: Text("Add favorites from a book's detail page.")
        )
      }
    }
  }
}

struct FavoriteRow: View {
  let favorite: Favorite
  let book: Book?

  var body: some View {
    VStack(alignment: .leading) {
      Text(book?.title ?? favorite.bookID).font(.headline)
      if !favorite.notes.isEmpty {
        Text(favorite.notes).font(.subheadline).foregroundStyle(.secondary)
      }
      Text(favorite.dateAdded, style: .date).font(.caption).foregroundStyle(.tertiary)
    }
  }
}
