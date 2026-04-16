import Foundation
import Testing

@testable import Splint

@Suite("Credential")
struct CredentialTests {
  private func makeCredential() -> Credential {
    // Unique per-test account to avoid keychain pollution between runs.
    // `synchronizable: false` keeps tests off iCloud Keychain.
    Credential(
      service: "co.searls.splint.tests",
      account: "test-\(UUID().uuidString)",
      synchronizable: false
    )
  }

  @Test func saveThenReadReturnsValue() throws {
    let c = makeCredential()
    defer { try? c.delete() }
    try c.save("hello")
    #expect(try c.read() == "hello")
  }

  @Test func deleteThenReadReturnsNil() throws {
    let c = makeCredential()
    try c.save("x")
    try c.delete()
    #expect(try c.read() == nil)
  }

  @Test func saveOverwritesExistingValue() throws {
    let c = makeCredential()
    defer { try? c.delete() }
    try c.save("first")
    try c.save("second")
    #expect(try c.read() == "second")
  }

  @Test func readReturnsNilWhenAbsent() throws {
    let c = makeCredential()
    #expect(try c.read() == nil)
  }

  @Test func deleteAbsentIsNotAnError() throws {
    let c = makeCredential()
    try c.delete()
    try c.delete()
  }
}
