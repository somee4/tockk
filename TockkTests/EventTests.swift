import XCTest
@testable import Tockk

final class EventTests: XCTestCase {
    func testDecodeValidEventJSON() throws {
        let json = """
        {
          "agent": "claude-code",
          "project": "site",
          "status": "success",
          "title": "Build complete",
          "summary": "3 files changed",
          "durationMs": 134000,
          "cwd": "/Users/x/site",
          "timestamp": "2026-04-20T10:30:00Z"
        }
        """.data(using: .utf8)!

        let event = try JSONDecoder.tockkDecoder.decode(Event.self, from: json)

        XCTAssertEqual(event.agent, "claude-code")
        XCTAssertEqual(event.project, "site")
        XCTAssertEqual(event.status, .success)
        XCTAssertEqual(event.title, "Build complete")
        XCTAssertEqual(event.durationMs, 134000)
    }

    func testDecodeMinimalEvent() throws {
        let json = #"{"agent":"codex","project":"x","status":"error","title":"Failed"}"#
            .data(using: .utf8)!
        let event = try JSONDecoder.tockkDecoder.decode(Event.self, from: json)
        XCTAssertEqual(event.status, .error)
        XCTAssertNil(event.summary)
        XCTAssertNil(event.durationMs)
    }

    func testDecodeGeneratesIdAndTimestampWhenAbsent() throws {
        let json = #"{"agent":"test","project":"p","status":"success","title":"t"}"#
            .data(using: .utf8)!
        let before = Date()
        let event = try JSONDecoder.tockkDecoder.decode(Event.self, from: json)
        // id is UUID — just verify it's not the zero UUID
        XCTAssertNotEqual(event.id.uuidString, "00000000-0000-0000-0000-000000000000")
        // timestamp should be "around now"
        XCTAssertGreaterThanOrEqual(event.timestamp.timeIntervalSince(before), -1.0)
        XCTAssertLessThanOrEqual(event.timestamp.timeIntervalSince1970, Date().timeIntervalSince1970 + 1.0)
    }

    func testDecodeThrowsOnWrongTypeForDurationMs() {
        let json = #"{"agent":"t","project":"p","status":"success","title":"x","durationMs":"fast"}"#
            .data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder.tockkDecoder.decode(Event.self, from: json))
    }
}
