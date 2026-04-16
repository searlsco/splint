import Foundation
import SwiftData

/// User-created, persistent entity. SwiftData owns the observation and
/// persistence story — Splint does not wrap or duplicate it.
@Model
public final class Favorite {
  public var bookID: String
  public var dateAdded: Date
  public var notes: String

  public init(bookID: String, dateAdded: Date = .now, notes: String = "") {
    self.bookID = bookID
    self.dateAdded = dateAdded
    self.notes = notes
  }
}
