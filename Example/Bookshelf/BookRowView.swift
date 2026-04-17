import SwiftUI

/// A row in the book list. Takes `let book: Book` — a pure value type —
/// so the view has no observation boundary at all. It re-evaluates only
/// when the parent's `ForEach` rebuilds with a structurally different
/// book.
public struct BookRowView: View {
  let book: Book
  let isFavorite: Bool
  let showCover: Bool

  public init(book: Book, isFavorite: Bool, showCover: Bool) {
    self.book = book
    self.isFavorite = isFavorite
    self.showCover = showCover
  }

  public var body: some View {
    HStack(spacing: 12) {
      if showCover {
        Rectangle()
          .fill(.secondary.opacity(0.2))
          .frame(width: 36, height: 48)
          .overlay(Image(systemName: "book"))
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(book.title).font(.headline)
        Text(book.author).font(.subheadline).foregroundStyle(.secondary)
        Text(book.genre).font(.caption).foregroundStyle(.tertiary)
      }
      Spacer()
      if isFavorite { Image(systemName: "heart.fill").foregroundStyle(.pink) }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(book.title), by \(book.author)\(isFavorite ? ", favorited" : "")")
  }
}

#Preview {
  BookRowView(
    book: Book(id: "1", title: "Refactoring", author: "Fowler", genre: "Nonfiction", year: 1999),
    isFavorite: true,
    showCover: true
  )
  .padding()
}
