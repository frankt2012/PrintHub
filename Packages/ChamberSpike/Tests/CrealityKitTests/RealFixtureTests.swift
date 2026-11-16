import XCTest
@testable import CrealityKit

final class RealFixtureTests: XCTestCase {
    func testK2PlusFirmware118IdleTelemetry() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: "k2-telemetry-fw1.1.8.0",
                withExtension: "jsonl",
                subdirectory: "Fixtures"
            )
        )

        let contents = try String(contentsOf: url, encoding: .utf8)
        var snapshot = PrinterSnapshot()

        for line in contents.split(separator: "\n") where !line.isEmpty {
            let outer = try JSONValue.decode(String(line))
            if let json = outer["json"] {
                snapshot.merge(json)
            }
        }

        XCTAssertEqual(snapshot.model, "F008")
        XCTAssertEqual(snapshot.friendlyModel, "K2 Plus")
        XCTAssertEqual(snapshot.hostname, "K2Plus-TEST")
        XCTAssertEqual(snapshot.firmwareVersion, "1.1.8.0")
        XCTAssertEqual(snapshot.stateCode, 0)
        XCTAssertEqual(snapshot.derivedState, .idle)
        XCTAssertEqual(snapshot.nozzleTemp, 26)
        XCTAssertEqual(snapshot.bedTemp, 23)
        XCTAssertEqual(snapshot.chamberTemp, 25)
        XCTAssertEqual(snapshot.bedTarget, 0)
        XCTAssertEqual(snapshot.chamberTarget, 0)
        XCTAssertEqual(snapshot.maxNozzleTemp, 350)
        XCTAssertEqual(snapshot.maxBedTemp, 120)
        XCTAssertEqual(snapshot.maxChamberTemp, 60)
        XCTAssertEqual(snapshot.cfsConnected, true)
        XCTAssertEqual(snapshot.errorCode, 0)
        XCTAssertFalse(snapshot.hasError)
        XCTAssertEqual(snapshot.fileName, nil)
        XCTAssertEqual(snapshot.progress, 0)
    }
}
