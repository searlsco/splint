import SwiftData
import SwiftUI
import Splint

/// Shows a book's details and lazily fetches extended metadata via a
/// `Job<BookMetadata>` owned as local `@State`. Persists a `Favorite`
/// row via SwiftData when the user taps "Add to Favorites."
public struct BookDetailView: View {
  let book: Book
  let client: BookClient

  @Environment(\.modelContext) private var modelContext
  @Query private var favorites: [Favorite]
  @State private var metadataJob = Job<BookMetadata>()

  public init(book: Book, client: BookClient) {
    self.book = book
    self.client = client
    let id = book.id
    _favorites = Query(filter: #Predicate<Favorite> { fav in
      fav.bookID == id
    })
  }

  public var body: some View {
    Form {
      Section("Book") {
        LabeledContent("Title", value: book.title)
        LabeledContent("Author", value: book.author)
        LabeledContent("Genre", value: book.genre)
        LabeledContent("Year", value: "\(book.year)")
      }
      Section("Metadata") {
        switch metadataJob.phase {
        case .idle, .running:
          ProgressView()
        case .completed:
          if let m = metadataJob.value {
            Text(m.description)
            LabeledContent("Pages", value: "\(m.pageCount)")
          }
        case .failed(let message):
          VStack(alignment: .leading) {
            Text("Couldn't load metadata").font(.headline)
            Text(message).font(.caption).foregroundStyle(.secondary)
            Button("Retry") { runMetadata() }
          }
        }
      }
      Section {
        if let existing = favorites.first {
          Button("Remove from Favorites", role: .destructive) {
            modelContext.delete(existing)
          }
          TextField("Notes", text: Binding(
            get: { existing.notes },
            set: { existing.notes = $0 }
          ))
        } else {
          Button("Add to Favorites") {
            modelContext.insert(Favorite(bookID: book.id))
          }
        }
      }
    }
    .navigationTitle(book.title)
    .task { runMetadata() }
  }

  private func runMetadata() {
    // `Job.run`'s `task:` is `sending` — region-based isolation accepts
    // the closure's disconnected copy of `self` even though
    // `BookDetailView` is not `Sendable` (it holds `@Query`,
    // `@Environment`, and `@State` property wrappers that aren't).
    // Under `@Sendable` this would fail to compile. We only read stable
    // `let` properties (`client`, `book`) — reaching into view state
    // (`@Query` results, mutating `@State`, etc.) from inside the Task
    // would still be wrong. See README "Job closures and isolation".
    metadataJob.run { try await client.fetchMetadata(book.id) }
  }
}
