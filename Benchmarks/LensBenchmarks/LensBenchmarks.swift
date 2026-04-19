import Benchmark
import Foundation
import Splint

// Large-N benchmarks for Lens, gated behind the `Benchmark` package trait.
// Setup (catalog construction + async fetch) runs on @MainActor via
// `await primeCatalog`; measurement starts in the task context; the measured
// work runs inside `MainActor.run`. This split keeps `benchmark`
// (task-isolated) out of the main-actor closure — calling `startMeasurement`
// on it there trips the Swift 6 region-based sendability check.
//
// Benchmark names avoid spaces and `+` because ordo-one/package-benchmark
// has asymmetric filename handling: `thresholds update` sanitizes spaces
// to underscores when writing JSON, but `thresholds check` reads by the
// original name — so a "Lens 1M updateFilter" benchmark's threshold file
// is never found at check time. Underscore names round-trip cleanly.

let benchmarks: @Sendable () -> Void = {
  let n = 1_000_000

  Benchmark.defaultConfiguration = .init(
    metrics: [.wallClock, .mallocCountTotal],
    warmupIterations: 1,
    maxDuration: .seconds(20),
    maxIterations: 20
  )

  // `relative` values are the ALLOWED DEVIATION (percentage above the stored
  // p90 baseline in Thresholds/) — not a ceiling on the metric itself.
  // 50% allows for machine/runner variance; a real regression that doubles
  // the baseline still trips the gate loudly.
  Benchmark(
    "Lens_1M_initFilterSort",
    configuration: .init(
      thresholds: [
        .wallClock: .init(relative: [.p90: 50.0]),
        .mallocCountTotal: .init(relative: [.p90: 25.0]),
      ]
    )
  ) { benchmark in
    let catalog = await primeCatalog(n: n)
    benchmark.startMeasurement()
    await MainActor.run {
      blackHole(
        Lens<BenchItem>(
          source: catalog,
          filter: { $0.score % 2 == 0 },
          sort: { $0.score < $1.score }
        )
      )
    }
  }

  Benchmark(
    "Lens_1M_updateFilter",
    configuration: .init(
      thresholds: [
        .wallClock: .init(relative: [.p90: 50.0]),
        .mallocCountTotal: .init(relative: [.p90: 25.0]),
      ]
    )
  ) { benchmark in
    let catalog = await primeCatalog(n: n)
    let lens = await MainActor.run { Lens<BenchItem>(source: catalog) }
    benchmark.startMeasurement()
    await MainActor.run {
      lens.updateFilter { $0.score % 2 == 0 }
    }
  }

  Benchmark(
    "Lens_1M_updateSort",
    configuration: .init(
      thresholds: [
        .wallClock: .init(relative: [.p90: 50.0]),
        .mallocCountTotal: .init(relative: [.p90: 25.0]),
      ]
    )
  ) { benchmark in
    let catalog = await primeCatalog(n: n)
    let lens = await MainActor.run {
      Lens<BenchItem>(source: catalog, filter: { $0.score % 2 == 0 })
    }
    benchmark.startMeasurement()
    await MainActor.run {
      lens.updateSort { $0.score < $1.score }
    }
  }

  Benchmark(
    "Lens_1M_pureFilter",
    configuration: .init(
      thresholds: [
        .wallClock: .init(relative: [.p90: 50.0]),
        .mallocCountTotal: .init(relative: [.p90: 25.0]),
      ]
    )
  ) { benchmark in
    let catalog = await primeCatalog(n: n)
    let lens = await MainActor.run { Lens<BenchItem>(source: catalog) }
    benchmark.startMeasurement()
    await MainActor.run {
      lens.updateFilter { $0.score > n / 2 }
    }
  }

  // GroupedLens: 32 buckets of ~31k items each — representative of a
  // real sectioned-list cardinality (not "one group" or "one item per
  // group"). Measures the grouping pass on top of filter+sort.
  Benchmark(
    "GroupedLens_1M_initFilterSortGrouping",
    configuration: .init(
      thresholds: [
        .wallClock: .init(relative: [.p90: 50.0]),
        .mallocCountTotal: .init(relative: [.p90: 25.0]),
      ]
    )
  ) { benchmark in
    let catalog = await primeCatalog(n: n)
    benchmark.startMeasurement()
    await MainActor.run {
      blackHole(
        GroupedLens<BenchItem, Int>(
          source: catalog,
          filter: { $0.score % 2 == 0 },
          sort: { $0.score < $1.score },
          categorize: { $0.score % 32 }
        )
      )
    }
  }

  Benchmark(
    "GroupedLens_1M_updateGrouping",
    configuration: .init(
      thresholds: [
        .wallClock: .init(relative: [.p90: 50.0]),
        .mallocCountTotal: .init(relative: [.p90: 25.0]),
      ]
    )
  ) { benchmark in
    let catalog = await primeCatalog(n: n)
    let lens = await MainActor.run {
      GroupedLens<BenchItem, Int>(source: catalog)
    }
    benchmark.startMeasurement()
    await MainActor.run {
      lens.updateCategories { $0.score % 32 }
    }
  }
}

// MARK: - Fixtures

struct BenchItem: Resource {
  let id: Int
  let score: Int
}

struct BenchCriteria: Equatable, Sendable {
  let tag: String
}

// Build a 1M-item catalog and wait (via yielding sleeps) for `load()` to
// finish. Using `RunLoop.main.run(until:)` here does NOT let the fetch
// Task's MainActor-hop callback run — the loop blocks main while we're
// trying to process main-actor work. `Task.sleep` yields cooperatively,
// which is what the existing test `waitUntil` helper does.
@MainActor
private func primeCatalog(n: Int) async -> Catalog<BenchItem, BenchCriteria> {
  let items = (0..<n).map { BenchItem(id: $0, score: $0) }
  let c = Catalog<BenchItem, BenchCriteria> { _ in items }
  c.load(BenchCriteria(tag: "bench"))
  let deadline = ContinuousClock.now.advanced(by: .seconds(30))
  while c.phase != .completed, ContinuousClock.now < deadline {
    try? await Task.sleep(for: .milliseconds(5))
  }
  precondition(c.phase == .completed, "catalog failed to load within 30s")
  return c
}
