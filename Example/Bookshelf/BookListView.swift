import SwiftData
import SwiftUI
import Splint

/// Renders the Bookshelf list from a single ``GroupedLens``. When the
/// toolbar grouping menu is set to `.none`, the body reads
/// `displayLens.items` directly; when set to `.author` or `.genre`, it
/// reads `displayLens.groups` and renders a sectioned `List`. The
/// search query and preferred genre both compose into the same
/// `updateFilter` call on the same lens — one list, one lens.
public struct BookListView: View {
  @Environment(\.displayLens) private var displayLens
  @Environment(\.bookSelection) private var selection
  @Query(sort: \Favorite.dateAdded) private var favorites: [Favorite]

  @Binding var query: String
  @State private var grouping: Grouping = .none

  enum Grouping: String, CaseIterable, Identifiable {
    case none, author, genre
    var id: String { rawValue }
    var label: String {
      switch self {
      case .none: "None"
      case .author: "Author"
      case .genre: "Genre"
      }
    }
  }

  public init(query: Binding<String>) {
    self._query = query
  }

  public var body: some View {
    // Without an injected selection, List selection writes go to a
    // throwaway instance and have no effect.
    @Bindable var selection = selection ?? Selection()

    List(selection: $selection.current) {
      if grouping == .none {
        ForEach(displayLens?.items ?? []) { book in
          BookListRow(book: book)
        }
      } else {
        ForEach(displayLens?.groups ?? [], id: \.category) { group in
          Section(group.category) {
            ForEach(group.items) { book in BookListRow(book: book) }
          }
        }
      }
    }
    .environment(\.favoriteBookIDs, Set(favorites.map(\.bookID)))
    .overlay { BookListEmptyState() }
    .searchable(text: $query)
    .toolbar {
      ToolbarItem {
        Menu {
          Picker("Group by", selection: $grouping) {
            ForEach(Grouping.allCases) { option in
              Text(option.label).tag(option)
            }
          }
        } label: {
          Label("Group by", systemImage: "square.stack.3d.up")
        }
        .accessibilityLabel("Group by")
      }
    }
    .onChange(of: grouping) { _, new in applyGrouping(new) }
    .navigationTitle("Bookshelf")
  }

  private func applyGrouping(_ g: Grouping) {
    switch g {
    case .none: displayLens?.updateCategories(nil)
    case .author: displayLens?.updateCategories(\.author)
    case .genre: displayLens?.updateCategories(\.genre)
    }
  }
}

extension EnvironmentValues {
  /// IDs of favorited books, injected by ``BookListView`` so each row
  /// reads favorite state itself instead of the list's row closure.
  @Entry var favoriteBookIDs: Set<String> = []
}

/// One list row. Takes only its `book`; favorite state and the cover
/// setting come from the environment, so a change to either updates
/// the rows without re-running ``BookListView``'s row closures.
private struct BookListRow: View {
  let book: Book

  @Environment(\.favoriteBookIDs) private var favoriteBookIDs
  @Environment(\.showCoversSetting) private var showCovers

  var body: some View {
    NavigationLink(value: book.id) {
      BookRowView(
        book: book,
        isFavorite: favoriteBookIDs.contains(book.id),
        showCover: showCovers?.value ?? true
      )
    }
  }
}

/// Loading, empty, and failure states shown over an empty list.
private struct BookListEmptyState: View {
  @Environment(\.bookCatalog) private var catalog
  @Environment(\.displayLens) private var displayLens

  var body: some View {
    if displayLens?.items.isEmpty ?? true {
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
}
