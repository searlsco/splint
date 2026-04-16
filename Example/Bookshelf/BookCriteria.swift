/// Criteria for ``Book`` catalogs. Even the "fetch all books" case is
/// parameterized in practice — you are always fetching from *somewhere*.
public struct BookCriteria: Equatable, Sendable {
  public let libraryID: String

  public init(libraryID: String) {
    self.libraryID = libraryID
  }
}
