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
      try? await Task.sleep(for: .milliseconds(50))
      return sampleBooks
    },
    fetchMetadata: { id in
      try? await Task.sleep(for: .milliseconds(50))
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
      try? await Task.sleep(for: .milliseconds(50))
      return sampleBooks
    },
    fetchMetadata: { id in
      _ = try? Credential(
        service: bookshelfCredentialService,
        account: bookshelfCredentialAccount,
        synchronizable: false
      ).read()
      try? await Task.sleep(for: .milliseconds(50))
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
  ]
}
