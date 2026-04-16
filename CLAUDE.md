# Splint

A multiplatform Swift library for data modeling — helpers, patterns, and
primitives that keep hot-path code fast. Born out of experimentation that
identified data modeling (not data/action flow) as the root cause of
performance issues in Justin's projects. Primary audience is Justin;
open-sourceable if anyone else finds it useful. Repo lives at
`github.com/searlsco/splint`. Module and product are both `Splint`.

This file captures the packaging, distribution, and infrastructure decisions
that shape the project. The library's API/design spec lives elsewhere and is
not re-litigated here.

## Current state of this repo

**This document is a forward-looking spec.** As of this commit, the repo
contains only scaffolding — `.claude/` (Claude + prove_it config and rules),
`script/test` and `script/test_fast` stubs, and this file. Everything else
described below — `Package.swift`, `Sources/`, `Tests/`, `.gitignore`,
`.swift-format`, `LICENSE`, `README.md`, `CHANGELOG.md`, `.spi.yml`,
`.github/workflows/`, `.claude/skills/release.md`, the remaining `script/*`
commands — is planned. Treat this file as the contract those artifacts must
satisfy when they're created, not a map of what already exists.

## Toolchain

- **Floor: Xcode 26.4+ / Swift 6.x.** Brand-new project, audience is Justin,
  latest toolchain only. No accommodations for older Xcode or Swift versions.
  Use macros, swift-testing, strict concurrency, and any other modern
  features without apology.

## Platforms

Supported: **macOS, iOS, tvOS, watchOS, visionOS.**

Linux was considered and dropped: `Credential.swift` imports `Security`,
which is Apple-only. Per the original hard rule — drop Linux the moment
it costs a single line of platform-shim code — Linux is out and
`.spi.yml`, CI, and this file all agree. Revisit only if the Keychain
dependency ever moves behind an optional target.

Consumers don't get deployment-target restrictions beyond what's declared in
`Package.swift`. The `platforms:` list only *customizes* deployment targets;
it doesn't gate where the package builds.

## Versioning & releases

- **Semver.** Start at `0.1.0`. While in `0.x`, minor bumps may break API
  freely.
- **Ship 1.0 only after battle-testing in 2+ of Justin's own projects.** No
  preemptive stability promises.
- **Tags are bare semver** — `0.1.0`, not `v0.1.0`. Matches Apple / swift-*
  ecosystem norm.
- **Deprecation policy: aggressive.** Breaking changes go out in the next
  major bump with no deprecation carry-over. Consumers pinning
  `.upToNextMajor(from:)` get a clean signal; consumers who want slower
  migration can stay on the old major.
- **Release flow:** `script/release <major|minor|patch>` is invoked by a
  Claude skill at `.claude/skills/release.md`. The script bumps the version,
  updates `CHANGELOG.md` (rolls `[Unreleased]` into a dated version section),
  runs `script/test`, creates a bare semver tag, and pushes.

## Dependencies

- **Zero runtime dependencies** in the library target. Every external dep
  becomes a dep our consumers inherit — we don't spend that budget casually.
- Test-only dependencies are fine, but keep them justified.

## Testing

- **swift-testing only.** No XCTest in new test files. `@Test` / `#expect`
  everywhere.
- Follow the project's testing rules in `.claude/rules/testing.md` (write
  tests first, one behavior per test, test behavior not implementation).
- Development follows BDD dual-loop TDD: a failing integration test drives
  inner unit-level red-green-refactor cycles until the integration test
  passes.

## Formatting & linting

- **swift-format only.** It ships with the toolchain — no brew install
  needed.
- Config lives at `.swift-format` in the repo root:
  ```json
  {
    "version": 1,
    "lineLength": 10000,
    "indentation": { "spaces": 2 },
    "filesToIgnore": [".build/**", "DerivedData/**"]
  }
  ```
  Line length is effectively unbounded — Justin hand-breaks lines where it
  reads best.

## License

**MIT.** A `LICENSE` file at the repo root is the sole source of truth.

## Package structure

- `.library(name: "Splint", targets: ["Splint"])` — **no forced linkage.**
  SPM and the consumer decide static vs dynamic.
- **Module/target split is deferred.** If macros or other build-time
  helpers emerge, they'll likely warrant their own target. Revisit before
  1.0, informed by actual usage.
- **`Package.resolved` is gitignored** — library convention, since consumers
  resolve against their own constraints.

## Public API hygiene

- Default-closed. `public` is deliberate; every public symbol is a semver
  commitment.
- `open` is rare — only where subclassing/overriding is explicitly part of
  the contract.
- Use `@_spi(Internal)` for escape hatches that need to cross the module
  boundary for tests or advanced users without becoming part of the semver
  surface.
- Reserve `package` for when the multi-target split happens.

## Documentation

- **Thin README:** one-paragraph pitch, install snippet, a tiny usage
  example, a link to the docs on Swift Package Index. That's it.
- **Rich DocC is the source of truth.** Catalog at
  `Sources/Splint/Splint.docc/` with a landing page, conceptual articles
  (e.g. "Modeling for performance"), and symbol-level docs. Every public
  symbol gets a `///` comment.
- **Hosted on Swift Package Index only.** `.spi.yml` at the repo root
  declares all supported platforms so SPI builds the compatibility matrix
  and DocC archive.
- `script/docs` produces a local preview; SPI handles the hosted docs.

## CI

- **GitHub Actions.** Workflows live in `.github/workflows/`.
- **Matrix:** `macOS-latest` (Xcode 26.4), one Swift version. Linux is
  not built (see Platforms above).
- Workflows invoke `script/test` rather than duplicating commands — the
  script is the single source of truth for what "pass" means locally and in
  CI.
- **Actions are pinned to major version tags** (e.g. `actions/checkout@v4`).
  No Dependabot; upgrades are manual.

## Git workflow

- **Direct commits to `main`.** No PR ceremony for solo work. Tags are cut
  from `main`.

## Community files

Keep it minimal until a real contributor shows up:

- `LICENSE`
- `README.md`
- `CHANGELOG.md` (Keep a Changelog format: `## [Unreleased]` at top, dated
  `## [X.Y.Z] - YYYY-MM-DD` sections below)

No `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, or issue/PR
templates until the project has traffic that warrants them.

## Repository files

- No README badges. The SPI page is the canonical status dashboard.
- `.gitignore` covers `.build/`, `.swiftpm/`, `DerivedData/`, `*.xcodeproj`,
  `Package.resolved`.

## `script/` suite

One-script-to-rule-them-all convention. Every dev-lifecycle action is a thin
shell script under `script/` so humans, CI, `prove_it`, and Claude skills
all invoke the same thing.

| Script | Purpose |
|---|---|
| `script/test` | Full test run. Invoked by CI and by `prove_it`. *(stub exists)* |
| `script/test_fast` | Quick-feedback subset used during the inner TDD loop. *(stub exists)* |
| `script/format` | `swift format --in-place --recursive Sources Tests` — mutates. |
| `script/lint` | `swift format lint --strict --recursive Sources Tests` — non-mutating; exits non-zero on violations. |
| `script/release <major\|minor\|patch>` | Bumps version, updates CHANGELOG, tags (bare semver), pushes. Invoked by the release Claude skill. |
| `script/docs` | Local DocC preview (`swift package generate-documentation --target Splint`). |
| `script/setup` | Fresh-clone bootstrap. Verifies toolchain; installs any repo-local tooling. |
| `script/clean` | Nukes `.build/`, `Package.resolved`, local docs output. |

## Claude skills

Project-scoped skills live in `.claude/skills/`:

- `release.md` — takes `major|minor|patch`, runs tests, edits CHANGELOG,
  invokes `script/release`, and handles the post-release verification.

## Deferred decisions (revisit before 1.0)

- **Target/product split** — whether to break out macros, build-time
  helpers, or integration-specific code (e.g. SwiftUI/Observation
  adapters) into their own targets. Decide based on real usage patterns.
- **Concurrency / Sendable posture** — Justin has a documented spec for this;
  apply it when implementing the data-modeling primitives, not now.
