import XCTest
@testable import Xcopper

final class FlagTests: XCTestCase {

	private func point(_ x: Double, _ y: Double) -> Point { Point(x: .mm(x), y: .mm(y)) }

	func testEverySymbolKindBringsExactlyOneFootprintToTheBoard() {
		var design = Design()
		for kind in Symbol.Kind.allCases {
			let before = design.board.footprints.count
			let ref = design.place(Symbol.Spec(kind: kind), at: point(20, 20))
			XCTAssertEqual(design.board.footprints.count, before + 1, kind.name)
			XCTAssertEqual(design.footprints(for: [ref]), [.footprint(before)], kind.name)
			XCTAssertEqual(design.schematic.symbols.last?.reference, design.board.footprints.last?.reference)
		}
		XCTAssertTrue(design.schematic.flags.isEmpty)
	}

	func testAFlagFromADocumentWrittenBeforeFlagsWereTheirOwnObject() throws {
		for kind in Flag.Kind.allCases {
			for rotation in Rotation.allCases {
				var design = Design()
				design.place(Symbol.Spec(kind: .resistor, value: "10k"), at: point(20, 20))
				design.place(Symbol.Spec(kind: .capacitor, value: "100n"), at: point(40, 20))
				let at = design.schematic.symbols[0].placedPins[0].at
				let expected = Flag(at: at, rotation: rotation, net: "SUPPLY", kind: kind)
				var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Document(design: design).encoded()) as? [String: Any])
				var sheet = try XCTUnwrap(json["schematic"] as? [String: Any])
				var symbols = try XCTUnwrap(sheet["symbols"] as? [[String: Any]])
				var legacy = symbols[0]
				legacy["kind"] = kind.rawValue
				legacy["at"] = ["x": at.x, "y": at.y]
				legacy["rotation"] = rotation.rawValue
				legacy["mirrored"] = true
				legacy["value"] = expected.net
				symbols.insert(legacy, at: 1)
				sheet["symbols"] = symbols
				sheet.removeValue(forKey: "flags")
				json["schematic"] = sheet

				var decoded = try Document.decode(JSONSerialization.data(withJSONObject: json))
				XCTAssertEqual(decoded.schematic.symbols, design.schematic.symbols)
				XCTAssertEqual(decoded.schematic.flags, [expected])
				XCTAssertEqual(decoded.board, design.board)
				XCTAssertEqual(Netlist(decoded.schematic).name(at: at), expected.net)
				XCTAssertEqual(decoded.updateBoardFromSchematic().assigned, 1)
				let net = decoded.nets.first { $0.name == expected.net }?.id
				XCTAssertNotNil(net)
				XCTAssertEqual(decoded.board.footprints[0].pads[0].net, net)
				XCTAssertEqual(try Document.decode(Document(design: decoded).encoded()), decoded)
			}
		}
	}

	func testADocumentWrittenBeforeFlagsExistedStillOpens() throws {
		var design = Design()
		design.place(Symbol.Spec(kind: .resistor), at: point(20, 20))
		var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Document(design: design).encoded()) as? [String: Any])
		var sheet = try XCTUnwrap(json["schematic"] as? [String: Any])
		sheet.removeValue(forKey: "flags")
		json["schematic"] = sheet
		XCTAssertEqual(try Document.decode(JSONSerialization.data(withJSONObject: json)), design)
	}

	func testCurrentFlagsAndLegacyFlagsSurviveTheSameDocument() throws {
		var design = Design()
		design.schematic.flags = [Flag(spec: .init(kind: .power, net: "VEE"), at: point(30, 30))]
		var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Document(design: design).encoded()) as? [String: Any])
		var sheet = try XCTUnwrap(json["schematic"] as? [String: Any])
		sheet["symbols"] = [["kind": "ground", "at": ["x": 0, "y": 0], "rotation": 0, "value": "GND"]]
		json["schematic"] = sheet
		let decoded = try Document.decode(JSONSerialization.data(withJSONObject: json))
		XCTAssertEqual(decoded.schematic.flags, design.schematic.flags + [Flag(spec: .init(kind: .ground), at: .zero)])
		XCTAssertTrue(decoded.schematic.symbols.isEmpty)
		XCTAssertEqual(try Document.decode(Document(design: decoded).encoded()), decoded)
	}

	func testAFlagDotsTheJunctionOnTheWireItStandsOn() {
		var schematic = Schematic()
		schematic.wires = [Wire(start: .zero, end: point(10, 0))]
		schematic.flags = [Flag(spec: .init(kind: .ground), at: point(5, 0))]
		XCTAssertEqual(schematic.junctions, [point(5, 0)])
		schematic.flags[0].at = .zero
		XCTAssertEqual(schematic.junctions, [])
		schematic.wires.append(Wire(start: .zero, end: point(0, -10)))
		XCTAssertEqual(schematic.junctions, [.zero])
	}

	func testAFlagTurnsAndFlipsWithoutLosingItsNet() throws {
		for kind in Flag.Kind.allCases {
			for rotation in Rotation.allCases {
				var schematic = Schematic()
				schematic.flags = [Flag(at: point(20, 20), rotation: rotation, net: "AGND", kind: kind)]
				let original = schematic.flags[0]
				schematic.rotate([.flag(0)], clockwise: true, around: original.at)
				XCTAssertEqual(schematic.flags[0].rotation, rotation.next)
				XCTAssertEqual(schematic.flags[0].at, original.at)
				XCTAssertEqual(schematic.flags[0].root, (original.root - original.at).rotated(.r90) + original.at)
				schematic.rotate([.flag(0)], clockwise: false, around: original.at)
				XCTAssertEqual(schematic.flags[0], original)

				let pivot = try XCTUnwrap(schematic.bounds(of: [.flag(0)])).center
				schematic.mirror([.flag(0)])
				XCTAssertEqual(schematic.flags[0].at, Point(x: 2 * pivot.x - original.at.x, y: original.at.y))
				XCTAssertEqual(schematic.flags[0].root, Point(x: 2 * pivot.x - original.root.x, y: original.root.y))
				XCTAssertEqual(schematic.flags[0].net, original.net)
				XCTAssertEqual(schematic.flags[0].kind, original.kind)
				schematic.mirror([.flag(0)])
				XCTAssertEqual(schematic.flags[0], original)
			}
		}
	}

	func testASheetPicksOutAFlagByItsGlyphAndItsStem() {
		for kind in Flag.Kind.allCases {
			for rotation in Rotation.allCases {
				let flag = Flag(at: point(20, 20), rotation: rotation, net: "NET", kind: kind)
				var schematic = Schematic()
				schematic.flags = [flag]
				schematic.wires = [Wire(start: flag.at, end: flag.root)]
				XCTAssertEqual(schematic.hitTest(at: flag.figure.bounds.center, tolerance: 0), .flag(0))
				for glyph in flag.placedGlyph {
					XCTAssertEqual(schematic.hitTest(at: glyph.bounds.origin, tolerance: 0), .flag(0))
				}
				XCTAssertEqual(schematic.refs(in: Rect(center: flag.at, size: .zero)), [.flag(0)])
				XCTAssertEqual(schematic.bounds(of: [.flag(0)]), flag.placedExtent)
				schematic.wires = []
				XCTAssertEqual(schematic.snapTarget(near: flag.at + point(0.2, 0.2), radius: .mm(0.5)), flag.at)
				XCTAssertTrue(schematic.isConnection(flag.at))
			}
		}
	}

	func testAFlagNamesAnIsolatedTerminalWithoutInventingAPart() {
		var schematic = Schematic()
		schematic.flags = [Flag(spec: .init(kind: .power, net: " VCC \n"), at: point(20, 20))]
		let group = Netlist(schematic).group(at: point(20, 20))
		XCTAssertEqual(group?.name, "VCC")
		XCTAssertEqual(group?.nodes, [])
		schematic.flags[0].net = " \n"
		XCTAssertNil(Netlist(schematic).name(at: point(20, 20)))
	}

	func testFindingANetPicksEveryMatchingFlagOnTheSheet() {
		var design = Design()
		design.schematic.flags = [
			Flag(spec: .init(kind: .ground), at: point(20, 20)),
			Flag(spec: .init(kind: .ground), at: point(40, 20)),
			Flag(spec: .init(kind: .power), at: point(60, 20)),
		]
		XCTAssertEqual(design.schematicRefs(matching: "gnd"), [.flag(0), .flag(1)])
		XCTAssertTrue(design.layoutRefs(matching: "gnd").isEmpty)
		XCTAssertTrue(design.schematicRefs(matching: "").isEmpty)
	}

	func testAParkedSymbolKeepsClearOfAFlagAlreadyDrawn() {
		var baseline = Design()
		baseline.place(Footprint.Spec(kind: .chip), at: point(20, 20))
		var design = Design()
		design.schematic.flags = [Flag(spec: .init(kind: .ground), at: baseline.schematic.symbols[0].at)]
		design.place(Footprint.Spec(kind: .chip), at: point(20, 20))
		XCTAssertFalse(design.schematic.symbols[0].placedExtent.intersects(design.schematic.flags[0].placedExtent))
	}
}
