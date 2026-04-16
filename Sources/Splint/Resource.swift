/// A marker protocol bundling the conformances every decoded remote value
/// needs: ``Identifiable`` for `ForEach`, ``Sendable`` for async boundaries,
/// ``Equatable`` and ``Hashable`` for collections, diffing, and
/// `NavigationLink` values.
///
/// `Resource` is deliberately minimal. It exists so agents can write
/// `struct Channel: Resource` instead of remembering which protocols to
/// adopt. Decodable is intentionally absent — not every resource comes from
/// JSON; conformers add `Decodable` or `Codable` themselves when needed.
public protocol Resource: Identifiable, Sendable, Equatable, Hashable
where ID: Hashable & Sendable {}
