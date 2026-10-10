import Foundation
import CDuckDB

// Only interrupt is called concurrently. The lock protects pointer lifetime and
// the sticky cancellation flag; the connection itself belongs to the worker.
public final class Cancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var connection: duckdb_connection?
    public init() {}
    public func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if let connection { duckdb_interrupt(connection) }
    }
    public func check() throws {
        lock.lock(); defer { lock.unlock() }
        if cancelled { throw CancellationError() }
    }
    fileprivate func attach(_ connection: duckdb_connection?) throws {
        lock.lock(); defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        self.connection = connection
    }
    fileprivate func detach() {
        lock.lock(); defer { lock.unlock() }; connection = nil
    }
}

final class Database {
    private var database: duckdb_database?
    private var connection: duckdb_connection?
    private let cancellation: Cancellation
    private let temporary: URL
    init(cancellation: Cancellation) throws {
        self.cancellation = cancellation
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent("DataScope-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        guard duckdb_open(nil, &database) == DuckDBSuccess else { throw ProfilingError("DuckDB konnte nicht geöffnet werden.") }
        guard duckdb_connect(database, &connection) == DuckDBSuccess else {
            duckdb_close(&database); throw ProfilingError("DuckDB-Verbindung fehlgeschlagen.")
        }
        do {
            try cancellation.attach(connection)
            try execute("SET autoinstall_known_extensions = false")
            try execute("SET autoload_known_extensions = false")
            try execute("SET threads = 4")
            try execute("SET memory_limit = '512MB'")
            try execute("SET temp_directory = \(literal(temporary.path))")
        } catch {
            cancellation.detach(); duckdb_disconnect(&connection); duckdb_close(&database)
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
    deinit {
        cancellation.detach(); duckdb_disconnect(&connection); duckdb_close(&database)
        try? FileManager.default.removeItem(at: temporary)
    }
    func execute(_ sql: String) throws { _ = try query(sql) }
    func query(_ sql: String) throws -> [[String?]] {
        try cancellation.check()
        var result = duckdb_result()
        defer { duckdb_destroy_result(&result) }
        let state = duckdb_query(connection, sql, &result)
        try cancellation.check()
        guard state == DuckDBSuccess else {
            let message = duckdb_result_error(&result).map { String(cString: $0) } ?? "Unbekannter DuckDB-Fehler"
            throw ProfilingError(message)
        }
        return (0..<duckdb_row_count(&result)).map { row in
            (0..<duckdb_column_count(&result)).map { column in
                if duckdb_value_is_null(&result, column, row) { return nil }
                guard let value = duckdb_value_varchar(&result, column, row) else { return nil }
                defer { duckdb_free(value) }
                return String(cString: value)
            }
        }
    }
}
func literal(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "''") + "'" }
func identifier(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }

public enum Profiler {
    public static func extensionURL() -> URL {
        if let path = ProcessInfo.processInfo.environment["DATASCOPE_EXCEL_EXTENSION"] { return URL(fileURLWithPath: path) }
        if let resource = Bundle.main.resourceURL?.appendingPathComponent("excel.duckdb_extension"),
           FileManager.default.fileExists(atPath: resource.path) { return resource }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Vendor/excel.duckdb_extension")
    }
    public static func run(url: URL, options: ImportOptions = .init(), cancellation: Cancellation = .init(),
                           progress: @Sendable (String) -> Void = { _ in }) throws -> Profile {
        let start = Date()
        try cancellation.check()
        let db = try Database(cancellation: cancellation)
        let format = url.pathExtension.lowercased()
        progress("Datei wird importiert …")
        let source: String
        if format == "xlsx" {
            let ext = extensionURL()
            guard FileManager.default.fileExists(atPath: ext.path) else { throw ProfilingError("Excel-Erweiterung fehlt. Bitte scripts/setup.sh ausführen.") }
            try db.execute("LOAD \(literal(ext.path))")
            let sheet = options.sheet.isEmpty ? "" : ", sheet=\(literal(options.sheet))"
            source = "read_xlsx(\(literal(url.path)), header=\(options.header), all_varchar=true, stop_at_empty=false\(sheet))"
        } else if ["csv", "tsv"].contains(format) {
            let delimiter = options.delimiter.isEmpty ? (format == "tsv" ? "\t" : "") : options.delimiter
            guard delimiter.utf8.count <= 4 else { throw ProfilingError("Das Trennzeichen darf höchstens vier UTF-8-Bytes haben.") }
            let delim = delimiter.isEmpty ? "" : ", delim=\(literal(delimiter))"
            source = "read_csv(\(literal(url.path)), header=\(options.header), all_varchar=true, allow_quoted_nulls=false, nullstr='', strict_mode=true, ignore_errors=false, skip=0, null_padding=false\(delim))"
        } else { throw ProfilingError("Bitte eine CSV-, TSV- oder XLSX-Datei auswählen.") }
        try db.execute("CREATE TABLE imported AS SELECT * FROM \(source)")
        let importSeconds = Date().timeIntervalSince(start)
        let rows = Int(try db.query("SELECT count(*) FROM imported")[0][0]!)!
        let names = try db.query("DESCRIBE imported").compactMap { $0[0] }
        var profiles: [ColumnProfile] = []
        for (index, name) in names.enumerated() {
            try cancellation.check()
            progress("Spalte \(index + 1) von \(names.count): \(name)")
            let col = identifier(name)
            // Normalize only for numeric interpretation. Raw values remain intact.
            let cleaned = "regexp_replace(\(col), '^\\s+|\\s+$', '', 'g')"
            let number = options.decimalComma
                ? "CASE WHEN regexp_full_match(\(cleaned), '[+-]?([0-9]+|[0-9]{1,3}(\\.[0-9]{3})+)(,[0-9]+)?') THEN try_cast(replace(replace(\(cleaned), '.', ''), ',', '.') AS DOUBLE) END"
                : "try_cast(\(cleaned) AS DOUBLE)"
            // Dates are intentionally limited to unambiguous, documented formats.
            // Do not infer dates from arbitrary numeric values such as IDs or scores.
            let date = """
                CASE
                    WHEN regexp_full_match(\(cleaned), '[0-9]{4}-[0-9]{2}-[0-9]{2}') THEN try_cast(\(cleaned) AS DATE)
                    WHEN regexp_full_match(\(cleaned), '[0-9]{2}\\.[0-9]{2}\\.[0-9]{4}') THEN try_strptime(\(cleaned), '%d.%m.%Y')::DATE
                    WHEN regexp_full_match(\(cleaned), '[0-9]{2}/[0-9]{2}/[0-9]{4}') THEN try_strptime(\(cleaned), '%d/%m/%Y')::DATE
                END
                """
            let result = try db.query("""
                WITH vals AS (SELECT \(col) AS v, \(cleaned) AS cleaned, \(number) AS n, \(date) AS d FROM imported)
                SELECT count(*) FILTER (WHERE v IS NULL),
                       count(*) FILTER (WHERE v = ''),
                       count(*) FILTER (WHERE v <> '' AND cleaned = ''),
                       count(DISTINCT v) FILTER (WHERE cleaned <> ''),
                       count(*) FILTER (WHERE isfinite(n)),
                       min(n) FILTER (WHERE isfinite(n)),
                       max(n) FILTER (WHERE isfinite(n)),
                       avg(n) FILTER (WHERE isfinite(n)),
                       count(*) FILTER (WHERE d IS NOT NULL),
                       count(*) FILTER (WHERE regexp_full_match(cleaned, '[+-]?(0|[1-9][0-9]*)')),
                       count(*) FILTER (WHERE isfinite(n) AND regexp_matches(cleaned, '[.,]')),
                       coalesce(max(char_length(v)), 0) FROM vals
                """)[0]
            let nulls = Int(result[0]!)!
            let empty = Int(result[1]!)!
            let whitespace = Int(result[2]!)!
            let numeric = Int(result[4]!)!
            let meaningful = rows - nulls - empty - whitespace
            let dateCount = Int(result[8]!)!
            let integerCount = Int(result[9]!)!
            let decimalCount = Int(result[10]!)!
            let dataType: InferredDataType
            if meaningful == 0 {
                dataType = .empty
            } else if dateCount == meaningful {
                dataType = .date
            } else if numeric == meaningful && integerCount == meaningful {
                dataType = .integer
            } else if numeric == meaningful && decimalCount > 0 {
                dataType = .decimal
            } else {
                dataType = .string
            }
            profiles.append(ColumnProfile(name: name, nulls: Int(result[0]!)!, empty: Int(result[1]!)!,
                                          whitespace: Int(result[2]!)!, distinct: Int(result[3]!)!, numeric: numeric,
                                          minimum: result[5].flatMap(Double.init), maximum: result[6].flatMap(Double.init),
                                          mean: result[7].flatMap(Double.init), dataType: dataType,
                                          maximumLength: Int(result[11]!)!))
        }
        let preview = try db.query("SELECT * FROM imported LIMIT 100")
        try cancellation.check()
        let bytes = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        return Profile(source: url.lastPathComponent, options: options, rows: rows, columns: profiles, preview: preview,
                       importSeconds: importSeconds, totalSeconds: Date().timeIntervalSince(start), fileBytes: bytes,
                       engineVersion: String(cString: duckdb_library_version()), createdAt: Date())
    }
}
