import XCTest
@testable import VantaSpeech

final class VantaSpeechTests: XCTestCase {

    func testAudioQualityBitrates() {
        XCTAssertEqual(AudioQuality.low.bitrate, "64k")
        XCTAssertEqual(AudioQuality.medium.bitrate, "96k")
        XCTAssertEqual(AudioQuality.high.bitrate, "128k")
    }

    func testAudioQualityRawValues() {
        XCTAssertEqual(AudioQuality(rawValue: "low"), .low)
        XCTAssertEqual(AudioQuality(rawValue: "medium"), .medium)
        XCTAssertEqual(AudioQuality(rawValue: "high"), .high)
        XCTAssertNil(AudioQuality(rawValue: "invalid"))
    }

    func testRecordingFormattedDuration() {
        let recording = Recording(
            title: "Test",
            duration: 125,
            audioFileURL: "/test.ogg"
        )
        XCTAssertEqual(recording.formattedDuration, "02:05")
    }

    func testRecordingFormattedDurationHours() {
        let recording = Recording(
            title: "Test",
            duration: 3725, // 1h 2m 5s
            audioFileURL: "/test.ogg"
        )
        XCTAssertEqual(recording.formattedDuration, "62:05")
    }
}
