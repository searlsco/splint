/// Extended metadata for a ``Book``, loaded on demand in the detail view
/// via a ``Splint.Job``.
public struct BookMetadata: Sendable, Equatable {
  public let description: String
  public let pageCount: Int

  public init(description: String, pageCount: Int) {
    self.description = description
    self.pageCount = pageCount
  }
}
