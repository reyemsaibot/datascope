import Foundation
import XCTest
@testable import ProfilingCore

final class ProfilingTests: XCTestCase {
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Fixtures")
    func testCSVPreservesRawValuesAndSeparatesMissingCategories() throws {
        let result = try Profiler.run(url: fixtures.appendingPathComponent("customers.csv"))
        XCTAssertEqual(result.rows, 4)
        XCTAssertEqual(result.preview[0][0], "00123")
        XCTAssertEqual(result.preview[3][3], "line one\nline two")
        let id = result.columns[0]
        XCTAssertEqual(id.distinct, 3)
        XCTAssertEqual(id.dataType, .string)
        XCTAssertEqual(id.maximumLength, 5)
        let email = result.columns[1]
        XCTAssertEqual(email.nulls, 1); XCTAssertEqual(email.empty, 1); XCTAssertEqual(email.whitespace, 1)
        XCTAssertEqual(email.distinct, 1)
        XCTAssertEqual(email.dataType, .string)
        let score = result.columns[2]
        XCTAssertEqual(score.numeric, 3); XCTAssertEqual(score.minimum, 10)
        XCTAssertEqual(score.maximum, 30); XCTAssertEqual(score.mean, 20)
        XCTAssertEqual(score.dataType, .integer)
        XCTAssertEqual(result.columns[3].maximumLength, 17)
    }
    func testGermanNumbers() throws {
        var options = ImportOptions(); options.delimiter = ";"; options.decimalComma = true
        let result = try Profiler.run(url: fixtures.appendingPathComponent("sales.csv"), options: options)
        XCTAssertEqual(result.rows, 4)
        XCTAssertEqual(result.preview[0][0], "0001")
        XCTAssertEqual(result.columns[1].numeric, 2)
        XCTAssertEqual(result.columns[1].mean, 623.5)
        XCTAssertEqual(result.columns[1].nulls, 1)
        XCTAssertEqual(result.columns[0].dataType, .string)
        XCTAssertEqual(result.columns[1].dataType, .string)
        XCTAssertEqual(result.columns[2].dataType, .string)
    }
    func testInfersIntegerDecimalAndDocumentedDateFormats() throws {
        try withCSV("whole,decimal,iso,german,slash,text,empty\n-12,1.50,2025-12-31,31.12.2025,31/12/2025,ABC,\n7,2.00,2026-01-01,01.01.2026,01/01/2026,XYZ,\n") { url in
            let result = try Profiler.run(url: url)
            XCTAssertEqual(result.columns.map(\.dataType), [.integer, .decimal, .date, .date, .date, .string, .empty])
            XCTAssertEqual(result.columns[5].maximumLength, 3)
            XCTAssertEqual(result.columns[6].maximumLength, 0)
        }
    }
    func testExcelIncludesRowsAfterBlankRowAndSelectsSheet() throws {
        let result = try Profiler.run(url: fixtures.appendingPathComponent("workbook.xlsx"))
        XCTAssertEqual(result.rows, 4)
        XCTAssertEqual(result.preview[0][0], "00123")
        XCTAssertEqual(result.columns[1].nulls, 2)
        XCTAssertEqual(result.columns[2].numeric, 3)
        XCTAssertEqual(result.columns[2].mean, 20)
        var options = ImportOptions(); options.sheet = "Umsatz"
        let second = try Profiler.run(url: fixtures.appendingPathComponent("workbook.xlsx"), options: options)
        XCTAssertEqual(second.rows, 2)
        XCTAssertEqual(second.columns[1].mean, 16.25)
        options.sheet = "Nicht vorhanden"
        XCTAssertThrowsError(try Profiler.run(url: fixtures.appendingPathComponent("workbook.xlsx"), options: options))
    }
    func testMalformedCSVIsNotSilentlyDiscarded() throws {
        try withCSV("a,b\n1,2\n3,4,5\n") { url in
            var options = ImportOptions(); options.delimiter = ","
            XCTAssertThrowsError(try Profiler.run(url: url, options: options))
        }
    }
    func testSQLCharactersInColumnNamesAndFileNames() throws {
        try withCSV("\"value\"\"; DROP TABLE imported;--\",normal\n10,ok\n") { url in
            let result = try Profiler.run(url: url)
            XCTAssertEqual(result.rows, 1); XCTAssertEqual(result.columns[0].mean, 10)
        }
    }
    func testHeaderOnlyAndAllNullColumns() throws {
        try withCSV("a,b\n") { url in
            let result = try Profiler.run(url: url)
            XCTAssertEqual(result.rows, 0); XCTAssertEqual(result.columns.count, 2)
            XCTAssertNil(result.columns[0].mean)
        }
        try withCSV("a,b\n,\n,\n") { url in
            let result = try Profiler.run(url: url)
            XCTAssertEqual(result.rows, 2); XCTAssertEqual(result.columns[0].nulls, 2)
            XCTAssertEqual(result.columns[0].distinct, 0)
        }
    }
    func testPreviewBoundedWhileStatisticsCoverEveryRow() throws {
        let csv = "id,value\n" + (0..<250).map { "\($0),\($0)" }.joined(separator: "\n")
        try withCSV(csv) { url in
            let result = try Profiler.run(url: url)
            XCTAssertEqual(result.rows, 250); XCTAssertEqual(result.preview.count, 100)
            XCTAssertEqual(result.columns[1].maximum, 249)
        }
    }
    func testCancellationBeforeStart() {
        let cancellation = Cancellation(); cancellation.cancel()
        XCTAssertThrowsError(try Profiler.run(url: fixtures.appendingPathComponent("customers.csv"), cancellation: cancellation)) {
            XCTAssertTrue($0 is CancellationError)
        }
    }
    func testInterruptRunningQueryAndFreshRunRecovers() throws {
        let cancellation = Cancellation()
        let db = try Database(cancellation: cancellation)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { cancellation.cancel() }
        let started = Date()
        XCTAssertThrowsError(try db.query("SELECT sum(sin(i::DOUBLE)) FROM range(10000000000) t(i)")) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        XCTAssertEqual(try Profiler.run(url: fixtures.appendingPathComponent("customers.csv")).rows, 4)
    }
    private func withCSV(_ contents: String, run: (URL) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DataScope-'" + UUID().uuidString + ".csv")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        try run(url)
    }
}
