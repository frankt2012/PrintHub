import XCTest
@testable import CameraKit

final class JPEGFrameParserTests: XCTestCase {
    private func jpeg(payload: [UInt8]) -> Data {
        Data([0xFF, 0xD8] + payload + [0xFF, 0xD9])
    }

    func testSingleFrame() {
        var parser = JPEGFrameParser()
        let frame = jpeg(payload: [1, 2, 3, 4])
        XCTAssertEqual(parser.append(frame), [frame])
    }

    func testFrameSplitAcrossChunks() {
        var parser = JPEGFrameParser()
        let frame = jpeg(payload: Array(repeating: 7, count: 100))

        XCTAssertTrue(parser.append(frame.subdata(in: 0..<1)).isEmpty)
        XCTAssertTrue(parser.append(frame.subdata(in: 1..<50)).isEmpty)
        XCTAssertEqual(parser.append(frame.subdata(in: 50..<frame.count)), [frame])
    }

    func testMultipleFramesWithMultipartNoise() {
        var parser = JPEGFrameParser()
        let one = jpeg(payload: [1, 2, 3])
        let two = jpeg(payload: [4, 5, 6])

        var stream = Data()
        stream.append(Data("--boundary\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
        stream.append(one)
        stream.append(Data("\r\n--boundary\r\n\r\n".utf8))
        stream.append(two)

        XCTAssertEqual(parser.append(stream), [one, two])
    }

    func testSplitMarkerAtBoundary() {
        var parser = JPEGFrameParser()
        let frame = jpeg(payload: [9, 9, 9])

        // Split between the two SOI bytes and again between the two EOI bytes.
        XCTAssertTrue(parser.append(Data([0xFF])).isEmpty)
        XCTAssertTrue(parser.append(Data([0xD8, 0x09, 0x09, 0x09])).isEmpty)
        XCTAssertEqual(parser.append(Data([0xFF])), [])
        XCTAssertEqual(parser.append(Data([0xD9])), [frame])
    }

    func testJunkBeforeFrameIsDiscarded() {
        var parser = JPEGFrameParser()
        let frame = jpeg(payload: [1, 2])
        let stream = Data("not a jpeg ".utf8) + frame
        XCTAssertEqual(parser.append(stream), [frame])
    }
}
