import XCTest
@testable import CrealityKit

final class JSONValueTests: XCTestCase {
    func testDecodesAndCoercesTelemetry() throws {
        let frame = try JSONValue.decode("""
        {
          "state": 1,
          "printFileName": "/usr/data/printer_data/gcodes/Benchy.gcode",
          "printProgress": "68.4",
          "printLeftTime": 4321,
          "nozzleTemp": "215.0",
          "bedTemp0": 60,
          "boxTemp": 38,
          "lightSw": 1,
          "layer": 84,
          "TotalLayer": 124,
          "model": "K2 Plus",
          "modelVersion": "F008",
          "err": { "errcode": 0 }
        }
        """)

        var snapshot = PrinterSnapshot()
        snapshot.merge(frame)

        XCTAssertEqual(snapshot.model, "K2 Plus")
        XCTAssertEqual(snapshot.modelVersion, "F008")
        XCTAssertEqual(snapshot.fileName, "Benchy.gcode")
        XCTAssertEqual(try XCTUnwrap(snapshot.progress), 68.4, accuracy: 0.001)
        XCTAssertEqual(snapshot.leftTime, 4321)
        XCTAssertEqual(snapshot.nozzleTemp, 215)
        XCTAssertEqual(snapshot.bedTemp, 60)
        XCTAssertEqual(snapshot.chamberTemp, 38)
        XCTAssertEqual(snapshot.layer, 84)
        XCTAssertEqual(snapshot.totalLayers, 124)
        XCTAssertEqual(snapshot.lightOn, true)
        XCTAssertEqual(snapshot.derivedState, .printing)
        XCTAssertEqual(snapshot.errorCode, 0)
        XCTAssertFalse(snapshot.hasError)
    }

    func testDeepMergeKeepsNestedState() throws {
        var snapshot = PrinterSnapshot()
        snapshot.merge(try JSONValue.decode("""
        { "boxsInfo": { "slot0": { "material": "PLA", "color": "red" }, "slot1": { "material": "PETG" } } }
        """))
        snapshot.merge(try JSONValue.decode("""
        { "boxsInfo": { "slot1": { "color": "blue" } }, "state": 1 }
        """))

        XCTAssertEqual(snapshot["boxsInfo"]?["slot0"]?["material"]?.stringValue, "PLA")
        XCTAssertEqual(snapshot["boxsInfo"]?["slot1"]?["material"]?.stringValue, "PETG")
        XCTAssertEqual(snapshot["boxsInfo"]?["slot1"]?["color"]?.stringValue, "blue")
        XCTAssertEqual(snapshot.stateCode, 1)
    }

    func testDerivedStates() throws {
        let cases: [(String, PrinterState)] = [
            (#"{ "state": 1 }"#, .printing),
            (#"{ "state": 5 }"#, .paused),
            (#"{ "state": 5, "pause": 1 }"#, .paused),
            (#"{ "state": 1, "err": { "errcode": 3 } }"#, .error),
            (#"{ "state": 1, "withSelfTest": 42 }"#, .selfTesting),
            (#"{ "state": 4 }"#, .stopped),
            (#"{ "state": 0 }"#, .idle),
            (#"{ "state": 0, "printFileName": "x.gcode" }"#, .processing),
            (#"{ "printFileName": "x.gcode", "printProgress": 100 }"#, .complete)
        ]

        for (json, expected) in cases {
            var snapshot = PrinterSnapshot()
            snapshot.merge(try JSONValue.decode(json))
            XCTAssertEqual(snapshot.derivedState, expected, "failed for \(json)")
        }
    }

    func testSummaryIsReadable() throws {
        var snapshot = PrinterSnapshot()
        snapshot.merge(try JSONValue.decode("""
        {
          "state": 1,
          "printFileName": "Benchy.gcode",
          "printProgress": 68.4,
          "printLeftTime": 4321,
          "nozzleTemp": 215,
          "targetNozzleTemp": 215,
          "bedTemp0": 60,
          "targetBedTemp": 60,
          "layer": 84,
          "TotalLayer": 124
        }
        """))

        XCTAssertTrue(snapshot.oneLineSummary.contains("printing"))
        XCTAssertTrue(snapshot.oneLineSummary.contains("68.4%"))
        XCTAssertTrue(snapshot.oneLineSummary.contains("Benchy.gcode"))
        XCTAssertTrue(snapshot.oneLineSummary.contains("nozzle 215/215°"))
    }

    func testDurationFormatting() {
        XCTAssertEqual(PrinterSnapshot.formatDuration(0), "0s")
        XCTAssertEqual(PrinterSnapshot.formatDuration(65), "1m 5s")
        XCTAssertEqual(PrinterSnapshot.formatDuration(4321), "1h 12m")
        XCTAssertEqual(PrinterSnapshot.formatDuration(-1), "—")
    }
}
