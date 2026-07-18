import XCTest
@testable import ClaudeMonitorBar

final class LocalUsageScannerTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalUsageScannerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("proj"),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Helpers

    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    private func assistantLine(
        model: String,
        ts: Date,
        msgId: String,
        reqId: String,
        input: Int = 10,
        output: Int = 5,
        cacheCreate: Int = 0,
        cacheRead: Int = 0
    ) -> String {
        "{\"type\":\"assistant\",\"timestamp\":\"\(iso(ts))\",\"requestId\":\"\(reqId)\"," +
        "\"message\":{\"id\":\"\(msgId)\",\"model\":\"\(model)\",\"usage\":{" +
        "\"input_tokens\":\(input),\"output_tokens\":\(output)," +
        "\"cache_creation_input_tokens\":\(cacheCreate),\"cache_read_input_tokens\":\(cacheRead)}}}"
    }

    @discardableResult
    private func write(_ lines: [String], to name: String = "s1.jsonl") throws -> URL {
        let url = tempDir.appendingPathComponent("proj/\(name)")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Tests

    func testAggregatesPerModel() async throws {
        let now = Date()
        try write([
            assistantLine(model: "claude-fable-5", ts: now, msgId: "m1", reqId: "r1", input: 100, output: 50, cacheRead: 1000),
            assistantLine(model: "claude-fable-5", ts: now, msgId: "m2", reqId: "r2", input: 200, output: 70),
            assistantLine(model: "claude-opus-4-8", ts: now, msgId: "m3", reqId: "r3", input: 10, output: 5),
        ])

        let stats = await LocalUsageScanner(root: tempDir).scan(now: now)

        XCTAssertEqual(stats.today.count, 2)
        let fable = try XCTUnwrap(stats.today.first { $0.model == "Fable" })
        XCTAssertEqual(fable.messages, 2)
        XCTAssertEqual(fable.inputTokens, 300)
        XCTAssertEqual(fable.outputTokens, 120)
        XCTAssertEqual(fable.cacheTokens, 1000)
        let opus = try XCTUnwrap(stats.today.first { $0.model == "Opus" })
        XCTAssertEqual(opus.messages, 1)
        // Sorted by output tokens descending
        XCTAssertEqual(stats.today.first?.model, "Fable")
    }

    func testDedupesByMessageAndRequestId() async throws {
        let now = Date()
        let dup = assistantLine(model: "claude-fable-5", ts: now, msgId: "m1", reqId: "r1", output: 50)
        try write([dup, dup], to: "a.jsonl")
        // Same message copied into a second (resumed) session file
        try write([dup], to: "b.jsonl")

        let stats = await LocalUsageScanner(root: tempDir).scan(now: now)

        let fable = try XCTUnwrap(stats.today.first { $0.model == "Fable" })
        XCTAssertEqual(fable.messages, 1)
        XCTAssertEqual(fable.outputTokens, 50)
    }

    func testSkipsSyntheticAndMalformedAndNonAssistant() async throws {
        let now = Date()
        try write([
            assistantLine(model: "<synthetic>", ts: now, msgId: "m1", reqId: "r1"),
            "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"assistant\"}}",
            "not json at all but mentions assistant",
            assistantLine(model: "claude-fable-5", ts: now, msgId: "m2", reqId: "r2", output: 7),
        ])

        let stats = await LocalUsageScanner(root: tempDir).scan(now: now)

        XCTAssertEqual(stats.today.count, 1)
        XCTAssertEqual(stats.today.first?.model, "Fable")
        XCTAssertEqual(stats.today.first?.outputTokens, 7)
    }

    func testAliasNormalization() async throws {
        let now = Date()
        try write([
            assistantLine(model: "sonnet", ts: now, msgId: "m1", reqId: "r1", output: 1),
            assistantLine(model: "claude-sonnet-5", ts: now, msgId: "m2", reqId: "r2", output: 2),
        ])

        let stats = await LocalUsageScanner(root: tempDir).scan(now: now)

        XCTAssertEqual(stats.today.count, 1)
        let sonnet = try XCTUnwrap(stats.today.first)
        XCTAssertEqual(sonnet.model, "Sonnet")
        XCTAssertEqual(sonnet.messages, 2)
        XCTAssertEqual(sonnet.outputTokens, 3)
    }

    func testDateFiltering() async throws {
        let now = Date()
        let yesterday = now.addingTimeInterval(-86400)
        let tenDaysAgo = now.addingTimeInterval(-10 * 86400)
        try write([
            assistantLine(model: "claude-fable-5", ts: now, msgId: "m1", reqId: "r1", output: 1),
            assistantLine(model: "claude-fable-5", ts: yesterday, msgId: "m2", reqId: "r2", output: 2),
            assistantLine(model: "claude-fable-5", ts: tenDaysAgo, msgId: "m3", reqId: "r3", output: 4),
        ])

        let stats = await LocalUsageScanner(root: tempDir).scan(now: now)

        let todayFable = try XCTUnwrap(stats.today.first { $0.model == "Fable" })
        XCTAssertEqual(todayFable.messages, 1)
        XCTAssertEqual(todayFable.outputTokens, 1)
        let weekFable = try XCTUnwrap(stats.week.first { $0.model == "Fable" })
        XCTAssertEqual(weekFable.messages, 2)
        XCTAssertEqual(weekFable.outputTokens, 3)
    }

    func testCacheInvalidationOnFileChange() async throws {
        let now = Date()
        let scanner = LocalUsageScanner(root: tempDir)
        try write([
            assistantLine(model: "claude-fable-5", ts: now, msgId: "m1", reqId: "r1", output: 1),
        ])

        let first = await scanner.scan(now: now)
        XCTAssertEqual(first.today.first?.messages, 1)

        try write([
            assistantLine(model: "claude-fable-5", ts: now, msgId: "m1", reqId: "r1", output: 1),
            assistantLine(model: "claude-fable-5", ts: now, msgId: "m2", reqId: "r2", output: 2),
        ])

        let second = await scanner.scan(now: now)
        XCTAssertEqual(second.today.first?.messages, 2)
        XCTAssertEqual(second.today.first?.outputTokens, 3)
    }

    func testMissingRootReturnsEmpty() async throws {
        let scanner = LocalUsageScanner(root: tempDir.appendingPathComponent("does-not-exist"))
        let stats = await scanner.scan()
        XCTAssertTrue(stats.isEmpty)
        XCTAssertTrue(stats.today.isEmpty)
    }
}
