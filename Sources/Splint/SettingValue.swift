import Foundation

/// Marker protocol for values that `UserDefaults` natively supports.
///
/// `URL` is deliberately absent — `UserDefaults` archives URLs via
/// `NSKeyedArchiver`, so a plain `object(forKey:) as? URL` round-trip fails
/// silently. Store URLs as `String`.
///
/// `Codable` structs are also absent — encoding arbitrary structs into
/// `Data` and stashing them in `UserDefaults` is an antipattern. Use
/// SwiftData for structured persistence.
public protocol SettingValue: Sendable {}

extension Bool: SettingValue {}
extension Int: SettingValue {}
extension Double: SettingValue {}
extension Float: SettingValue {}
extension String: SettingValue {}
extension Data: SettingValue {}
extension Date: SettingValue {}
extension Array: SettingValue where Element: SettingValue {}
extension Dictionary: SettingValue where Key == String, Value: SettingValue {}
