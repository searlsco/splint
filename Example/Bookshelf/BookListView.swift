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
  @Environment(\.bookCatalog) private var catalog
  @Environment(\.displayLens) private var displayLens
  @Environment(\.bookSelection) private var selection
  @Environment(\.showCoversSetting) private var showCovers
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
    List(selection: Binding(
      get: { selection?.current },
      set: { selection?.current = $0 }
    )) {
      if grouping == .none {
        ForEach(displayLens?.items ?? []) { book in
          row(for: book)
        }
      } else {
        ForEach(displayLens?.groups ?? [], id: \.category) { group in
          Section(group.category) {
            ForEach(group.items) { book in row(for: book) }
          }
        }
      }
    }
    .overlay { emptyStateOverlay }
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

  private func row(for book: Book) -> some View {
    NavigationLink(value: book.id) {
      BookRowView(
        book: book,
        isFavorite: favorites.contains { $0.bookID == book.id },
        showCover: showCovers?.value ?? true
      )
    }
  }

  @ViewBuilder
  private var emptyStateOverlay: some View {
    let items = displayLens?.items ?? []
    if items.isEmpty {
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

  private func applyGrouping(_ g: Grouping) {
    switch g {
    case .none: displayLens?.updateCategories(nil)
    case .author: displayLens?.updateCategories { $0.author }
    case .genre: displayLens?.updateCategories { $0.genre }
    }
  }
}
