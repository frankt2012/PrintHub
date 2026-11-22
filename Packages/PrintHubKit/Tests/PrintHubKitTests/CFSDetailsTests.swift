import XCTest
@testable import PrintHubKit

final class CFSDetailsTests: XCTestCase {
    func testParsesBrandAndProductFromBoxsInfo() throws {
        let message = try JSONValue.decode("""
        {
          "boxsInfo": {
            "materialBoxs": [
              {
                "id": 1,
                "type": 0,
                "state": 1,
                "materials": [
                  {
                    "id": 0,
                    "vendor": "Creality",
                    "type": "PLA",
                    "name": "Hyper PLA",
                    "rfid": "101001",
                    "color": "#0c12e1f",
                    "state": 2
                  },
                  {
                    "id": 1,
                    "vendor": "Generic",
                    "type": "PLA",
                    "name": "Generic PLA",
                    "color": "#0ffffff",
                    "state": 1
                  },
                  {
                    "id": 2,
                    "vendor": "None",
                    "type": "-1",
                    "name": "unknown",
                    "color": "-1"
                  }
                ]
              },
              {
                "id": 0,
                "type": 1,
                "materials": [
                  { "id": 0, "vendor": "Acme", "type": "PETG", "name": "Acme PETG" }
                ]
              }
            ]
          }
        }
        """)

        let details = try XCTUnwrap(CFSDetails.parse(message))
        XCTAssertEqual(details.slots.count, 2)

        let creality = try XCTUnwrap(details.slots["T1A"])
        XCTAssertEqual(creality.brand, "Creality")
        XCTAssertEqual(creality.productName, "Hyper PLA")
        XCTAssertEqual(creality.material, "PLA")
        XCTAssertEqual(creality.colorHex, "#C12E1F")

        let generic = try XCTUnwrap(details.slots["T1B"])
        XCTAssertEqual(generic.brand, "Generic")
        XCTAssertEqual(generic.productName, "Generic PLA")

        XCTAssertNil(details.slots["T1C"])
        XCTAssertNil(details.slots["side_spool"])
    }

    func testMergesDetailsIntoSlots() throws {
        let box = try JSONValue.decode("""
        {
          "state": "connect",
          "filament": 1,
          "T1": {
            "state": "connect",
            "color_value": ["0c12e1f", "0ffffff", "0aabbcc", "0ddeeff"],
            "material_type": ["000001", "000001", "000001", "000001"]
          }
        }
        """)

        let message = try JSONValue.decode("""
        {
          "boxsInfo": {
            "materialBoxs": [
              {
                "id": 1,
                "type": 0,
                "materials": [
                  { "id": 0, "vendor": "Creality", "type": "PLA", "name": "Hyper PLA", "color": "#0c12e1f" },
                  { "id": 1, "vendor": "Generic", "type": "PLA", "name": "Generic PLA", "color": "#0ffffff" },
                  { "id": 2, "vendor": "Acme", "type": "PETG", "name": "Acme PETG", "color": "#0111111" }
                ]
              }
            ]
          }
        }
        """)

        let details = try XCTUnwrap(CFSDetails.parse(message))
        let state = CFSState.parse(box).applying(details)
        let slots = try XCTUnwrap(state.units.first?.slots)

        XCTAssertEqual(slots[0].brand, "Creality")
        XCTAssertEqual(slots[0].displayName, "Creality Hyper PLA")
        XCTAssertEqual(slots[1].displayName, "Generic PLA")
        // The printer reports this slot as a different colour now, so the
        // stored Acme profile must not be attached to it.
        XCTAssertNil(slots[2].brand)
        XCTAssertEqual(slots[2].displayName, "PLA")
        XCTAssertNil(slots[3].brand)
    }

    func testDisplayNameFallsBackToMaterial() {
        let slot = CFSSlot(
            id: "T1A",
            material: "PLA",
            colorHex: "#FFFFFF",
            remaining: nil,
            isPresent: true
        )
        XCTAssertEqual(slot.displayName, "PLA")

        let branded = CFSSlot(
            id: "T1A",
            material: "PLA",
            colorHex: "#FFFFFF",
            remaining: nil,
            isPresent: true,
            brand: "Acme"
        )
        XCTAssertEqual(branded.displayName, "Acme PLA")

        let generic = CFSSlot(
            id: "T1A",
            material: "PLA",
            colorHex: "#FFFFFF",
            remaining: nil,
            isPresent: true,
            brand: "Generic",
            productName: "Kingroon PLA"
        )
        XCTAssertEqual(generic.displayName, "Kingroon PLA")
    }
}
