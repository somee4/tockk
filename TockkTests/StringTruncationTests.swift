import XCTest
@testable import Tockk

final class StringTruncationTests: XCTestCase {

    func testReturnsOriginalWhenUnderLimit() {
        XCTAssertEqual("short".truncatedMiddle(maxChars: 10), "short")
    }

    func testReturnsOriginalAtExactLimit() {
        XCTAssertEqual("abcdefghij".truncatedMiddle(maxChars: 10), "abcdefghij")
    }

    func testTruncatesAtMiddleWithEllipsis() {
        // 30-char input truncated to 10 total chars:
        //   head = ceil((10-1)/2) = 5, tail = 10-1-5 = 4  →  "abcde…wxyz"
        let input = "abcdefghijklmnopqrstuvwxyz0123"
        let result = input.truncatedMiddle(maxChars: 10)
        XCTAssertEqual(result.count, 10)
        XCTAssertTrue(result.contains("…"))
        XCTAssertTrue(result.hasPrefix("abcde"))
        XCTAssertTrue(result.hasSuffix("0123"))
    }

    func testHandlesHangulWithoutSplittingGrapheme() {
        let input = "한글로 된 아주 긴 빌드 제목입니다 정말로요"
        let result = input.truncatedMiddle(maxChars: 10)
        XCTAssertEqual(result.count, 10)
        XCTAssertTrue(result.contains("…"))
    }

    func testHandlesEmojiGrapheme() {
        let input = "build ✅✅✅ finished with 🎉🎉🎉 results"
        let result = input.truncatedMiddle(maxChars: 12)
        XCTAssertEqual(result.count, 12)
        XCTAssertTrue(result.contains("…"))
    }

    func testMaxCharsLessThanTwoFallsBackToEllipsis() {
        // Degenerate input: cannot produce head + … + tail. Return single ellipsis.
        XCTAssertEqual("anything".truncatedMiddle(maxChars: 1), "…")
        XCTAssertEqual("anything".truncatedMiddle(maxChars: 0), "…")
    }

    func testMaxCharsOfTwoProducesHeadAndEllipsis() {
        // Boundary budget: maxChars=2 → budget=1, head=1 char, tail=0 → "a…".
        // Guards the smallest non-degenerate truncation.
        XCTAssertEqual("anything".truncatedMiddle(maxChars: 2), "a…")
    }
}
