import Foundation
import SwiftData
import Testing
@testable import Bookshelf

@MainActor
@Suite("Favorites SwiftData")
struct FavoritesTests {
  private func inMemoryContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: Favorite.self, configurations: config)
  }

  @Test func insertFavorite() throws {
    let container = try inMemoryContainer()
    let ctx = container.mainContext
    let fav = Favorite(bookID: "1", notes: "loved it")
    ctx.insert(fav)
    try ctx.save()

    let fetched = try ctx.fetch(FetchDescriptor<Favorite>())
    #expect(fetched.count == 1)
    #expect(fetched.first?.bookID == "1")
    #expect(fetched.first?.notes == "loved it")
  }

  @Test func deleteFavorite() throws {
    let container = try inMemoryContainer()
    let ctx = container.mainContext
    let fav = Favorite(bookID: "2")
    ctx.insert(fav)
    try ctx.save()
    ctx.delete(fav)
    try ctx.save()
    let fetched = try ctx.fetch(FetchDescriptor<Favorite>())
    #expect(fetched.isEmpty)
  }

  @Test func updateNotes() throws {
    let container = try inMemoryContainer()
    let ctx = container.mainContext
    let fav = Favorite(bookID: "3", notes: "")
    ctx.insert(fav)
    try ctx.save()
    fav.notes = "updated"
    try ctx.save()
    let fetched = try ctx.fetch(FetchDescriptor<Favorite>())
    #expect(fetched.first?.notes == "updated")
  }
}
