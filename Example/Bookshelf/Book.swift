import Foundation
import Splint

/// A book returned by the mock `BookClient`. Immutable value type — a
/// textbook ``Resource``.
public struct Book: Resource, Codable {
  public let id: String
  public let title: String
  public let author: String
  public let genre: String
  public let year: Int
  public let coverURL: URL?

  public init(
    id: String,
    title: String,
    author: String,
    genre: String,
    year: Int,
    coverURL: URL? = nil
  ) {
    self.id = id
    self.title = title
    self.author = author
    self.genre = genre
    self.year = year
    self.coverURL = coverURL
  }
}
