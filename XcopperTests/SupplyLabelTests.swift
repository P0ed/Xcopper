import XCTest
@testable import Xcopper

final class SupplyLabelTests: XCTestCase {

	private func point(_ x: µm, _ y: µm) -> Point { Point(x: x, y: y) }

	func testEverySymbolKindBringsExactlyOneFootprintToTheBoard() {
		var design = Design()
		for kind in Symbol.Kind.allCases {
			let before = design.board.footprints.count
			let ref = design.place(Symbol.Spec(kind: kind), at: point(20 * .mm, 20 * .mm))
			XCTAssertEqual(design.board.footprints.count, before + 1, kind.name)
			XCTAssertEqual(design.footprints(for: [ref]), [.footprint(before)], kind.name)
			XCTAssertEqual(design.schematic.symbols.last?.reference, design.board.footprints.last?.reference)
		}
		XCTAssertTrue(design.schematic.labels.isEmpty)
	}

	func testLegacyPowerSymbolsOpenAsNetLabels() throws {
		for kind in ["power", "ground"] {
			for rotation in Rotation.allCases {
				var design = Design()
				design.place(Symbol.Spec(kind: .resistor, value: "10k"), at: point(20 * .mm, 20 * .mm))
				design.place(Symbol.Spec(kind: .capacitor, value: "100n"), at: point(40 * .mm, 20 * .mm))
				let at = design.schematic.symbols[0].placedPins[0].at
				let expected = NetLabel(at: at, text: "SUPPLY")
				var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Document(design: design).encoded()) as? [String: Any])
				var sheet = try XCTUnwrap(json["schematic"] as? [String: Any])
				var symbols = try XCTUnwrap(sheet["symbols"] as? [[String: Any]])
				var legacy = symbols[0]
				legacy["kind"] = kind
				legacy["at"] = ["x": at.x, "y": at.y]
				legacy["rotation"] = rotation.rawValue
				legacy["mirrored"] = true
				legacy["value"] = expected.text
				symbols.insert(legacy, at: 1)
				sheet["symbols"] = symbols
				sheet.removeValue(forKey: "flags")
				json["schematic"] = sheet

				var decoded = try Document.decode(JSONSerialization.data(withJSONObject: json))
				XCTAssertEqual(decoded.schematic.symbols, design.schematic.symbols)
				XCTAssertEqual(decoded.schematic.labels, [expected])
				XCTAssertEqual(decoded.board, design.board)
				XCTAssertEqual(Netlist(decoded.schematic).name(at: at), expected.text)
				XCTAssertEqual(decoded.updateBoardFromSchematic().assigned, 1)
				let net = decoded.nets.first { $0.name == expected.text }?.id
				XCTAssertNotNil(net)
				XCTAssertEqual(decoded.board.footprints[0].pads[0].net, net)
				XCTAssertEqual(try Document.decode(Document(design: decoded).encoded()), decoded)
			}
		}
	}

	func testADocumentWrittenBeforeFlagsExistedStillOpens() throws {
		var design = Design()
		design.place(Symbol.Spec(kind: .resistor), at: point(20 * .mm, 20 * .mm))
		var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Document(design: design).encoded()) as? [String: Any])
		var sheet = try XCTUnwrap(json["schematic"] as? [String: Any])
		sheet.removeValue(forKey: "flags")
		json["schematic"] = sheet
		XCTAssertEqual(try Document.decode(JSONSerialization.data(withJSONObject: json)), design)
	}

	func testSavedFlagsAndLegacyPowerSymbolsOpenTogetherAsLabels() throws {
		let design = Design()
		var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Document(design: design).encoded()) as? [String: Any])
		var sheet = try XCTUnwrap(json["schematic"] as? [String: Any])
		sheet["flags"] = [["kind": "power", "at": ["x": 30 * .mm, "y": 30 * .mm], "rotation": 3, "net": "VEE"]]
		sheet["symbols"] = [["kind": "ground", "at": ["x": 0, "y": 0], "rotation": 0, "value": "GND"]]
		json["schematic"] = sheet
		let decoded = try Document.decode(JSONSerialization.data(withJSONObject: json))
		XCTAssertEqual(decoded.schematic.labels, [NetLabel(at: point(30 * .mm, 30 * .mm), text: "VEE"), NetLabel(at: .zero, text: "GND")])
		XCTAssertTrue(decoded.schematic.symbols.isEmpty)
		let encoded = try Document(design: decoded).encoded()
		let written = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
		let writtenSheet = try XCTUnwrap(written["schematic"] as? [String: Any])
		XCTAssertNil(writtenSheet["flags"])
		XCTAssertEqual(try Document.decode(encoded), decoded)
	}

	func testMigratingAFlagKeepsTheLabelThatOverrodeItsNetName() throws {
		for legacySymbol in [false, true] {
			var design = Design()
			design.schematic.wires = [Wire(start: .zero, end: point(10 * .mm, 0))]
			design.schematic.labels = [NetLabel(at: .zero, text: "SIGNAL")]
			var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Document(design: design).encoded()) as? [String: Any])
			var sheet = try XCTUnwrap(json["schematic"] as? [String: Any])
			sheet[legacySymbol ? "symbols" : "flags"] = [[
				"kind": "ground", "at": ["x": 5 * .mm, "y": 0], "rotation": 0,
				legacySymbol ? "value" : "net": "GND",
			]]
			json["schematic"] = sheet
			let decoded = try Document.decode(JSONSerialization.data(withJSONObject: json))
			XCTAssertEqual(decoded.schematic.labels, design.schematic.labels + [NetLabel(at: point(5 * .mm, 0), text: "SIGNAL")])
			XCTAssertEqual(Netlist(decoded.schematic).name(at: point(10 * .mm, 0)), "SIGNAL")
		}
	}

	func testMigratingAFlagAtAModulePortKeepsItsSupplyAssignment() throws {
		var design = Design()
		design.place(Symbol.Spec(kind: .resistor), at: point(20 * .mm, 20 * .mm))
		let at = design.schematic.symbols[0].placedPins[0].at
		design.schematic.labels = [NetLabel(at: at, text: "#SUPPLY")]
		var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Document(design: design).encoded()) as? [String: Any])
		var sheet = try XCTUnwrap(json["schematic"] as? [String: Any])
		sheet["flags"] = [["kind": "power", "at": ["x": at.x, "y": at.y], "rotation": 0, "net": "VCC"]]
		json["schematic"] = sheet
		let decoded = try Document.decode(JSONSerialization.data(withJSONObject: json))
		XCTAssertEqual(decoded.schematic.labels.map(\.text), ["#SUPPLY", "VCC"])
		let projection = decoded.moduleProjection(syncNative: true)
		XCTAssertEqual(projection.ports["SUPPLY"], decoded.nets.first { $0.name == "VCC" }?.id)
		XCTAssertEqual(projection.design.board.footprints[0].pads[0].net, projection.ports["SUPPLY"])
	}

	func testALabelAtACrossingMakesAJunction() {
		var schematic = Schematic()
		schematic.wires = [Wire(start: .zero, end: point(10 * .mm, 0)), Wire(start: point(5 * .mm, -5 * .mm), end: point(5 * .mm, 5 * .mm))]
		XCTAssertEqual(schematic.junctions, [])
		schematic.labels = [NetLabel(at: point(5 * .mm, 0), text: "GND")]
		XCTAssertEqual(schematic.junctions, [point(5 * .mm, 0)])
		XCTAssertEqual(Netlist(schematic).name(at: point(5 * .mm, 5 * .mm)), "GND")
	}

	func testALabelNamesAnIsolatedTerminalWithoutInventingAPart() {
		var schematic = Schematic()
		schematic.labels = [NetLabel(at: point(20 * .mm, 20 * .mm), text: " VCC \n")]
		let group = Netlist(schematic).group(at: point(20 * .mm, 20 * .mm))
		XCTAssertEqual(group?.name, "VCC")
		XCTAssertEqual(group?.nodes, [])
		schematic.labels[0].text = " \n"
		XCTAssertNil(Netlist(schematic).name(at: point(20 * .mm, 20 * .mm)))
	}

	func testFindingANetPicksEveryMatchingLabelOnTheSheet() {
		var design = Design()
		design.schematic.labels = [
			NetLabel(at: point(20 * .mm, 20 * .mm), text: "GND"),
			NetLabel(at: point(40 * .mm, 20 * .mm), text: "GND"),
			NetLabel(at: point(60 * .mm, 20 * .mm), text: "VCC"),
		]
		XCTAssertEqual(design.schematicRefs(matching: "gnd"), [.label(0), .label(1)])
		XCTAssertTrue(design.layoutRefs(matching: "gnd").isEmpty)
		XCTAssertTrue(design.schematicRefs(matching: "").isEmpty)
	}

	func testAParkedSymbolKeepsClearOfALabelAlreadyDrawn() {
		var baseline = Design()
		baseline.place(Footprint.Spec(kind: .chip), at: point(20 * .mm, 20 * .mm))
		var design = Design()
		design.schematic.labels = [NetLabel(at: baseline.schematic.symbols[0].at, text: "GND")]
		design.place(Footprint.Spec(kind: .chip), at: point(20 * .mm, 20 * .mm))
		XCTAssertFalse(design.schematic.symbols[0].placedExtent.intersects(design.schematic.labels[0].bounds))
	}
}
