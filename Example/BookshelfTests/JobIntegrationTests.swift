import Foundation
import Testing
import Splint
@testable import Bookshelf

@MainActor
@Suite("Bookshelf Job integration")
struct JobIntegrationTests {
  private func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: () -> Bool
  ) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
      if condition() { return }
      try? await Task.sleep(for: .milliseconds(5))
    }
  }

  @Test func fetchMetadataLifecycle() async {
    let job = Job<BookMetadata>()
    let client = BookClient.mock
    job.run {
      try await client.fetchMetadata("1")
    }
    await waitUntil { job.phase == .completed }
    #expect(job.value != nil)
    #expect(job.value?.pageCount ?? 0 > 0)
  }

  @Test func cancelClearsPhaseKeepsValue() async {
    let job = Job<BookMetadata>()
    let client = BookClient.mock
    job.run { try await client.fetchMetadata("1") }
    await waitUntil { job.phase == .completed }
    let keep = job.value
    job.cancel()
    #expect(job.phase == .idle)
    #expect(job.value == keep)
  }

  @Test func resetClearsValue() async {
    let job = Job<BookMetadata>()
    let client = BookClient.mock
    job.run { try await client.fetchMetadata("1") }
    await waitUntil { job.value != nil }
    job.reset()
    #expect(job.value == nil)
    #expect(job.phase == .idle)
  }
}
