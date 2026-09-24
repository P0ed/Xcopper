import SwiftUI
import XCTest
@testable import Xcopper

final class SupplyLabelTests: XCTestCase {

	private func point(_ x: µm, _ y: µm) -> Point { Point(x: x, y: y) }

	private func design() -> Design {
		var design = Design()
		for x in [20, 40, 60] {
			design.place(Symbol.Spec(kind: .resistor), at: point(x * .mm, 20 * .mm))
		}
		return design
	}

	func testEverySymbolKindBringsExactlyOneFootprintToTheBoard() {
		var design = Design()
		for kind in Symbol.Kind.allCases {
			let before = design.board.footprints.count
			let ref = design.place(Symbol.Spec(kind: kind), at: point(20 * .mm, 20 * .mm))
			XCTAssertEqual(design.board.footprints.count, before + 1, kind.name)
			XCTAssertEqual(design.footprints(for: [ref]), [.footprint(before)], kind.name)
			XCTAssertEqual(design.board.footprints.last?.symbolKind, kind)
		}
		XCTAssertTrue(design.board.symbols.flatMap(\.pins).allSatisfy { $0.netLabel == nil })
	}

	func testPinLabelsNormalizeNamesAndConnectSeparateSymbols() {
		var design = design()
		design.board.footprints[0].symbol.pins[0].netLabel = " VCC \n"
		design.board.footprints[1].symbol.pins[0].netLabel = "VCC"
		let one = design.board.footprints[0].symbol.placedPins[0].at
		let two = design.board.footprints[1].symbol.placedPins[0].at
		let netlist = Netlist(design.board)
		XCTAssertEqual(netlist.name(at: one), "VCC")
		XCTAssertEqual(netlist.group(at: one), netlist.group(at: two))
		design.board.footprints[0].symbol.pins[0].netLabel = nil
		XCTAssertNil(Netlist(design.board).name(at: one))
		XCTAssertEqual(Netlist(design.board).name(at: two), "VCC")
	}

	func testFindingANetSelectsTheSymbolsThatSpecifyIt() {
		var design = design()
		for (index, name) in ["GND", "GND", "#1 OUT1"].enumerated() {
			design.board.footprints[index].symbol.pins[0].netLabel = name
		}
		XCTAssertEqual(design.schematicRefs(matching: "gnd"), [.symbol(0), .symbol(1)])
		XCTAssertEqual(design.layoutRefs(matching: "gnd"), [.footprint(0), .footprint(1)])
		XCTAssertEqual(design.schematicRefs(matching: "out1"), [.symbol(2)])
		XCTAssertTrue(design.schematicRefs(matching: "").isEmpty)
	}

	func testLabelsFollowPinTransformsAndSurviveDocumentRoundTrip() throws {
		var design = design()
		design.board.footprints[0].symbol.pins[0].netLabel = "#1 OUT1"
		design.board.footprints[0].symbol.rotation = .r90
		design.board.footprints[0].symbol.mirrored = true
		let pin = design.board.footprints[0].symbol.placedPins[0]
		XCTAssertEqual(pin.netLabel, "#1 OUT1")
		XCTAssertEqual(pin.netName, "OUT1")
		XCTAssertEqual(Netlist(design.board).name(at: pin.at), "OUT1")
		XCTAssertEqual(try Document.decode(Document(design: design).encoded()), design)
	}

	@MainActor
	func testModulePinInspectorEditsSynchronizeAndStoreEmptyAsNone() {
		var design = Design()
		design.modules = [ModuleInstance(reference: "M1", filename: "Part.xcb", interface: [IODesignator(number: 1, name: "OUT1")])]
		let harness = EditorHarness(design: design)
		harness.perform { $0.design.modules[0][netLabel: "1"] = "#10 BUS" }
		XCTAssertEqual(harness.design.modules[0].symbol.pins[0].netLabel, "#10 BUS")
		XCTAssertTrue(harness.design.nets.contains { $0.name == "BUS" })
		XCTAssertFalse(harness.design.nets.contains { $0.name == "#10 BUS" })
		harness.perform { $0.design.modules[0][netLabel: "1"] = "" }
		XCTAssertNil(harness.design.modules[0].netLabels)
		XCTAssertNil(harness.design.modules[0].symbol.pins[0].netLabel)
		harness.undo.undo()
		XCTAssertEqual(harness.design.modules[0].symbol.pins[0].netLabel, "#10 BUS")
	}
}
