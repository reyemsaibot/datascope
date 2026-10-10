import Foundation

public struct ImportOptions: Sendable, Codable {
    public var delimiter = "" // empty = detect
    public var header = true
    public var sheet = "" // empty = first worksheet
    public var decimalComma = false
    public init() {}
}
public struct ColumnProfile: Sendable, Codable, Identifiable {
    public var id: String { name }
    public let name: String
    public let nulls: Int
    public let empty: Int
    public let whitespace: Int
    public let distinct: Int
    public let numeric: Int
    public let minimum: Double?
    public let maximum: Double?
    public let mean: Double?
    public var missing: Int { nulls + empty + whitespace }
}
public struct Profile: Sendable, Codable {
    public let source: String
    public let options: ImportOptions
    public let rows: Int
    public let columns: [ColumnProfile]
    public let preview: [[String?]]
    public let importSeconds: Double
    public let totalSeconds: Double
    public let fileBytes: Int64
    public let engineVersion: String
    public let createdAt: Date
}
public struct ProfilingError: LocalizedError, Sendable {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}
