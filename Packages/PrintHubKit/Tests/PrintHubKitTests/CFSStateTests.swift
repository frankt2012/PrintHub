import XCTest
@testable import PrintHubKit

final class CFSStateTests: XCTestCase {
    func testParsesConnectedCFSWithFourSlots() throws {
        let box = try JSONValue.decode("""
        {
          "state": "connect",
          "filament": 1,
          "filament_useup": 1,
          "same_material": [
            ["000001", "07a92ac", ["T1B"], "PLA"],
            ["000001", "0ff1e1e", ["T1C"], "PLA"],
            ["000001", "0000000", ["T1D"], "PLA"]
          ],
          "T1": {
            "state": "connect",
            "temperature": "24",
            "dry_and_humidity": "40",
            "remain_len": ["0", "-1", "-1", "-1"],
            "color_value": ["-1", "07a92ac", "0ff1e1e", "0000000"],
            "material_type": ["-1", "000001", "000001", "000001"],
            "type": "CFS"
          },
          "T2": { "state": "None" }
        }
        """)

        let state = CFSState.parse(box)
        XCTAssertTrue(state.connected)
        XCTAssertTrue(state.filamentUseUp)
        XCTAssertEqual(state.units.count, 1)

        let unit = try XCTUnwrap(state.units.first)
        XCTAssertEqual(unit.id, "T1")
        XCTAssertEqual(unit.temperature, 24)
        XCTAssertEqual(unit.humidity, 40)
        XCTAssertEqual(unit.slots.count, 4)

        XCTAssertFalse(unit.slots[0].isPresent)
        XCTAssertEqual(unit.slots[1].material, "PLA")
        XCTAssertEqual(unit.slots[1].colorHex, "#7A92AC")
        XCTAssertEqual(unit.slots[2].colorHex, "#FF1E1E")
        XCTAssertEqual(unit.slots[3].colorHex, "#000000")
    }
}

extension CFSStateTests {
    func testDisconnectedCFSHasNoUnits() throws {
        let box = try JSONValue.decode("""
        {
          "state": "None",
          "filament": 0,
          "filament_useup": 0,
          "T1": { "state": "None", "color_value": ["-1", "-1", "-1", "-1"], "material_type": ["-1", "-1", "-1", "-1"] },
          "T2": { "state": "None" },
          "T3": { "state": "None" },
          "T4": { "state": "None" }
        }
        """)

        let state = CFSState.parse(box)
        XCTAssertFalse(state.connected)
        XCTAssertTrue(state.units.isEmpty)
    }

    func testEmptySlotsUseSentinels() throws {
        let box = try JSONValue.decode("""
        {
          "state": "connect",
          "filament": 1,
          "T1": {
            "state": "connect",
            "remain_len": ["-1", "-1", "-1", "-1"],
            "color_value": ["-1", "-1", "-1", "-1"],
            "material_type": ["-1", "-1", "-1", "-1"]
          }
        }
        """)

        let unit = try XCTUnwrap(CFSState.parse(box).units.first)
        XCTAssertTrue(unit.slots.allSatisfy { !$0.isPresent })
        XCTAssertTrue(unit.slots.allSatisfy { $0.remainingValue == nil })
        XCTAssertNil(unit.temperature)
        XCTAssertNil(unit.humidity)
    }

    func testUnknownMaterialFallsBackToNumericID() throws {
        let box = try JSONValue.decode("""
        {
          "state": "connect",
          "filament": 1,
          "T1": {
            "state": "connect",
            "material_type": ["000009", "-1", "-1", "-1"],
            "color_value": ["112233", "-1", "-1", "-1"]
          }
        }
        """)

        let unit = try XCTUnwrap(CFSState.parse(box).units.first)
        XCTAssertEqual(unit.slots[0].material, "Material 000009")
        XCTAssertEqual(unit.slots[0].colorHex, "#112233")
    }
}
