import Foundation
import Splint

/// Injected API. A closure struct — no protocol, no DI container, no
/// singleton. `.mock` returns hardcoded books after a short delay so the
/// example app has no network dependency.
public struct BookClient: Sendable {
  public var fetchBooks: @Sendable (BookCriteria) async throws -> [Book]
  public var fetchMetadata: @Sendable (String) async throws -> BookMetadata

  public init(
    fetchBooks: @escaping @Sendable (BookCriteria) async throws -> [Book],
    fetchMetadata: @escaping @Sendable (String) async throws -> BookMetadata = { _ in
      BookMetadata(description: "", pageCount: 0)
    }
  ) {
    self.fetchBooks = fetchBooks
    self.fetchMetadata = fetchMetadata
  }
}

extension BookClient {
  /// In-process fixtures. Production code constructs `.live` with real
  /// networking; this example only uses the mock.
  public static let mock = BookClient(
    fetchBooks: { _ in
      try? await Task.sleep(for: .milliseconds(5000))
      return sampleBooks
    },
    fetchMetadata: { id in
      try? await Task.sleep(for: .milliseconds(5000))
      return BookMetadata(
        description: "A fine book about \(id).",
        pageCount: 200 + (abs(id.hashValue) % 400)
      )
    }
  )

  /// "Real" client shape — reads the keychain-backed API token on every
  /// call (not cached) to prove `Credential` composes with request-time
  /// auth. The response body is still mocked because the example app has
  /// no network dependency; a production client would attach `token` to
  /// an `Authorization` header on a real `URLRequest` here.
  public static let live = BookClient(
    fetchBooks: { _ in
      _ = try? Credential(
        service: bookshelfCredentialService,
        account: bookshelfCredentialAccount,
        synchronizable: false
      ).read()
      try? await Task.sleep(for: .milliseconds(5000))
      return sampleBooks
    },
    fetchMetadata: { id in
      _ = try? Credential(
        service: bookshelfCredentialService,
        account: bookshelfCredentialAccount,
        synchronizable: false
      ).read()
      try? await Task.sleep(for: .milliseconds(5000))
      return BookMetadata(
        description: "A fine book about \(id).",
        pageCount: 200 + (abs(id.hashValue) % 400)
      )
    }
  )

  static let sampleBooks: [Book] = [
    Book(id: "1", title: "The Pragmatic Programmer", author: "Hunt & Thomas", genre: "Nonfiction", year: 1999),
    Book(id: "2", title: "The Three-Body Problem", author: "Liu Cixin", genre: "Fiction", year: 2008),
    Book(id: "3", title: "Refactoring", author: "Martin Fowler", genre: "Nonfiction", year: 1999),
    Book(id: "4", title: "Annihilation", author: "Jeff VanderMeer", genre: "Fiction", year: 2014),
    Book(id: "5", title: "The Design of Everyday Things", author: "Don Norman", genre: "Nonfiction", year: 1988),
    Book(id: "6", title: "The Dark Forest", author: "Liu Cixin", genre: "Fiction", year: 2008),
    Book(id: "7", title: "Death's End", author: "Liu Cixin", genre: "Fiction", year: 2010),
    Book(id: "8", title: "Authority", author: "Jeff VanderMeer", genre: "Fiction", year: 2014),
    Book(id: "9", title: "Acceptance", author: "Jeff VanderMeer", genre: "Fiction", year: 2014),
    Book(id: "10", title: "Working Effectively with Legacy Code", author: "Michael Feathers", genre: "Nonfiction", year: 2004),
    Book(id: "11", title: "Growing Object-Oriented Software", author: "Freeman & Pryce", genre: "Nonfiction", year: 2009),
    Book(id: "12", title: "The Mythical Man-Month", author: "Fred Brooks", genre: "Nonfiction", year: 1975),
    Book(id: "13", title: "A Memory Called Empire", author: "Arkady Martine", genre: "Fiction", year: 2019),
    Book(id: "14", title: "A Desolation Called Peace", author: "Arkady Martine", genre: "Fiction", year: 2021),
    Book(id: "15", title: "Piranesi", author: "Susanna Clarke", genre: "Fiction", year: 2020),
  ]
}
