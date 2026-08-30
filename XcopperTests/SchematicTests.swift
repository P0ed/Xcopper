import SwiftUI
import XCTest
@testable import Xcopper

final class SchematicTests: XCTestCase {

	func testContextualToolShortcutsMatchAcrossEditors() {
		XCTAssertEqual(SchematicTool.symbol.shortcutCharacter, "F")
		XCTAssertEqual(Tool.footprint.shortcutCharacter, "F")
		XCTAssertEqual(SchematicTool.wire.shortcutCharacter, "W")
		XCTAssertEqual(Tool.trace.shortcutCharacter, "W")
	}

	private func wire(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Wire {
		Wire(start: Pt(x: .mm(ax), y: .mm(ay)), end: Pt(x: .mm(bx), y: .mm(by)))
	}

	// MARK: Connectivity

	func testATJunctionConnectsButACrossingDoesNot() {
		var schematic = Schematic()
		schematic.wires = [
			wire(0, 0, 10, 0),
			wire(5, 0, 5, 10), // ends on the middle of the first: a T
			wire(0, 20, 10, 20),
			wire(5, 15, 5, 25), // passes straight over the third: an X
		]
		let netlist = Netlist(schematic)

		XCTAssertEqual(
			netlist.group(at: Pt(x: 0, y: 0))?.points,
			netlist.group(at: Pt(x: .mm(5), y: .mm(10)))?.points
		)
		XCTAssertNotEqual(
			netlist.group(at: Pt(x: 0, y: .mm(20)))?.points,
			netlist.group(at: Pt(x: .mm(5), y: .mm(15)))?.points
		)
	}

	func testJunctionDotsAppearOnlyWhereThreeConductorsMeet() {
		var schematic = Schematic()
		schematic.wires = [wire(0, 0, 10, 0), wire(5, 0, 5, 10)]
		XCTAssertEqual(schematic.junctions, [Pt(x: .mm(5), y: 0)])

		schematic.wires = [wire(0, 0, 5, 0), wire(5, 0, 10, 0)]
		XCTAssertEqual(schematic.junctions, [])
	}

	func testALabelNamesItsNetAndOverridesAPowerFlag() {
		var schematic = Schematic()
		schematic.wires = [wire(0, 0, 10, 0)]
		XCTAssertNil(Netlist(schematic).name(at: Pt(x: 0, y: 0)))

		schematic.labels = [NetLabel(at: Pt(x: .mm(4), y: 0), text: "SDA")]
		XCTAssertEqual(Netlist(schematic).name(at: Pt(x: .mm(10), y: 0)), "SDA")

		// An explicit label is the more deliberate act, so it wins
		schematic.symbols = [
			Symbol(spec: .init(kind: .power), reference: "#PWR1", at: Pt(x: 0, y: 0)),
		]
		XCTAssertEqual(schematic.symbols[0].value, "VCC")
		XCTAssertEqual(Netlist(schematic).name(at: Pt(x: .mm(10), y: 0)), "SDA")

		schematic.labels = []
		XCTAssertEqual(Netlist(schematic).name(at: Pt(x: .mm(10), y: 0)), "VCC")
	}

	func testAGroundSymbolNamesTheNetItTouches() {
		var schematic = Schematic()
		schematic.wires = [wire(0, 0, 10, 0)]
		schematic.symbols = [
			Symbol(spec: .init(kind: .ground), reference: "#PWR1", at: Pt(x: .mm(10), y: 0)),
		]
		XCTAssertEqual(schematic.symbols[0].value, "GND")
		XCTAssertEqual(Netlist(schematic).name(at: Pt(x: 0, y: 0)), "GND")
	}

	func testPinsOnTheSameWireLandInOneGroup() {
		var schematic = Schematic()
		schematic.symbols = [
			Symbol(spec: .init(kind: .resistor), reference: "R1", at: .zero),
			Symbol(spec: .init(kind: .resistor), reference: "R2", at: Pt(x: .mm(20), y: 0)),
		]
		let right = schematic.symbols[0].placedPins[1].at
		let left = schematic.symbols[1].placedPins[0].at
		schematic.wires = [Wire(start: right, end: left)]

		let group = Netlist(schematic).group(at: right)
		XCTAssertEqual(group?.nodes, [.init(symbol: 0, pin: 1), .init(symbol: 1, pin: 0)])
	}

	// MARK: Geometry

	func testOrthogonalSnapPicksTheDominantAxis() {
		let origin = Pt.zero
		XCTAssertEqual(snapped90(from: origin, to: Pt(x: .mm(10), y: .mm(2))), Pt(x: .mm(10), y: 0))
		XCTAssertEqual(snapped90(from: origin, to: Pt(x: .mm(2), y: .mm(10))), Pt(x: 0, y: .mm(10)))
		XCTAssertEqual(snapped90(from: origin, to: Pt(x: .mm(5), y: .mm(5))), Pt(x: .mm(5), y: 0))
	}

	func testSymbolRotationAndMirroringPlacePinsAbsolutely() {
		let at = Pt(x: .mm(10), y: .mm(20))
		var symbol = Symbol(spec: .init(kind: .resistor), reference: "R1", at: at)

		XCTAssertEqual(symbol.placedPins.map(\.at), [
			Pt(x: .mm(4.92), y: .mm(20)),
			Pt(x: .mm(15.08), y: .mm(20)),
		])
		XCTAssertEqual(symbol.placedPins.map(\.direction), [.r180, .r0])

		symbol.rotation = .r90
		XCTAssertEqual(symbol.placedPins.map(\.at), [
			Pt(x: .mm(10), y: .mm(14.92)),
			Pt(x: .mm(10), y: .mm(25.08)),
		])
		XCTAssertEqual(symbol.placedPins.map(\.direction), [.r270, .r90])

		symbol.rotation = .r0
		symbol.mirrored = true
		XCTAssertEqual(symbol.placedPins.map(\.at), [
			Pt(x: .mm(15.08), y: .mm(20)),
			Pt(x: .mm(4.92), y: .mm(20)),
		])
		XCTAssertEqual(symbol.placedPins.map(\.direction), [.r0, .r180])
	}

	func testPinLegsRunBackTowardsTheBody() {
		let symbol = Symbol(spec: .init(kind: .resistor), reference: "R1", at: .zero)
		let pins = symbol.placedPins

		XCTAssertEqual(pins[0].root, Pt(x: -.mm(2.54), y: 0))
		XCTAssertEqual(pins[1].root, Pt(x: .mm(2.54), y: 0))
	}

	func testICPinsRunDownTheLeftSideAndBackUpTheRight() {
		let symbol = Symbol(spec: .init(kind: .ic, pins: 8), reference: "U1", at: .zero)
		XCTAssertEqual(symbol.pins.map(\.number), (1 ... 8).map { "\($0)" })
		XCTAssertEqual(symbol.pins[0].direction, .r180)
		XCTAssertEqual(symbol.pins[7].direction, .r0)

		// Pin 1 sits opposite pin 8, pin 4 opposite pin 5
		XCTAssertEqual(symbol.pins[0].at.y, symbol.pins[7].at.y)
		XCTAssertEqual(symbol.pins[3].at.y, symbol.pins[4].at.y)
	}

	func testHitTestAndRubberBandSelectionCoverEveryKind() {
		var schematic = Schematic()
		schematic.symbols = [Symbol(spec: .init(kind: .resistor), reference: "R1", at: Pt(x: .mm(10), y: .mm(10)))]
		schematic.wires = [wire(0, 30, 10, 30)]
		schematic.labels = [NetLabel(at: Pt(x: .mm(2), y: .mm(30)), text: "CLK")]

		XCTAssertEqual(schematic.hitTest(at: Pt(x: .mm(10), y: .mm(10)), tolerance: 0), .symbol(0))
		XCTAssertEqual(schematic.hitTest(at: Pt(x: .mm(8), y: .mm(30)), tolerance: 0), .wire(0))
		XCTAssertNil(schematic.hitTest(at: Pt(x: .mm(60), y: .mm(60)), tolerance: 0))

		let all = Rect(from: .zero, to: Pt(x: .mm(50), y: .mm(50)))
		XCTAssertEqual(schematic.refs(in: all), [.symbol(0), .wire(0), .label(0)])
	}

	func testDuplicateOffsetsCopiesAndRenamesSymbols() {
		var schematic = Schematic()
		schematic.symbols = [Symbol(spec: .init(kind: .resistor), reference: "R1", at: Pt(x: .mm(10), y: .mm(10)))]
		let created = schematic.duplicate([.symbol(0)], by: Pt(x: .mm(5), y: 0))

		XCTAssertEqual(created, [.symbol(1)])
		XCTAssertEqual(schematic.symbols[1].reference, "R2")
		XCTAssertEqual(schematic.symbols[1].at, Pt(x: .mm(15), y: .mm(10)))
	}

	func testMirroringASelectionFlipsAroundItsOwnCentre() {
		var schematic = Schematic()
		schematic.symbols = [
			Symbol(spec: .init(kind: .resistor), reference: "R1", at: Pt(x: .mm(10), y: 0)),
			Symbol(spec: .init(kind: .resistor), reference: "R2", at: Pt(x: .mm(30), y: 0)),
		]
		schematic.mirror([.symbol(0), .symbol(1)])

		XCTAssertEqual(schematic.symbols[0].at.x, .mm(30))
		XCTAssertEqual(schematic.symbols[1].at.x, .mm(10))
		XCTAssertTrue(schematic.symbols.allSatisfy(\.mirrored))
	}

	// MARK: Pushing the netlist onto the board

	private func wiredDesign() -> Design {
		var design = Design(board: Board(size: Size(width: .mm(50), height: .mm(40)), stack: .two))
		design.schematic.symbols = [
			Symbol(spec: .init(kind: .resistor), reference: "R1", at: .zero),
			Symbol(spec: .init(kind: .ic, pins: 8), reference: "U1", at: Pt(x: .mm(40), y: 0)),
		]
		let from = design.schematic.symbols[0].placedPins[1].at
		let to = design.schematic.symbols[1].placedPins[6].at
		design.schematic.wires = [Wire(start: from, end: to)]
		design.schematic.labels = [NetLabel(at: from, text: "SDA")]

		design.board.footprints = [
			Footprint(spec: .init(kind: .chip, chip: .c0603), reference: "R1", at: Pt(x: .mm(10), y: .mm(10))),
			Footprint(spec: .init(kind: .soic, pins: 8), reference: "U1", at: Pt(x: .mm(30), y: .mm(20))),
		]
		return design
	}

	func testUpdateBoardAssignsPadNetsByReferenceAndPinNumber() {
		var design = wiredDesign()
		let report = design.updateBoardFromSchematic()

		XCTAssertEqual(report.assigned, 2)
		XCTAssertEqual(report.created, ["SDA"])
		XCTAssertTrue(report.isClean)

		let sda = design.nets.first { $0.name == "SDA" }?.id
		XCTAssertNotNil(sda)
		XCTAssertEqual(design.board.footprints[0].pads.first { $0.name == "2" }?.net, sda)
		XCTAssertEqual(design.board.footprints[1].pads.first { $0.name == "7" }?.net, sda)
		XCTAssertNil(design.board.footprints[0].pads.first { $0.name == "1" }?.net)
	}

	func testUpdateBoardReportsWhatItCouldNotMatch() {
		var design = wiredDesign()
		design.board.footprints.removeFirst()
		design.board.footprints.append(
			Footprint(spec: .init(kind: .header, pins: 2), reference: "J1", at: Pt(x: .mm(5), y: .mm(5)))
		)
		let report = design.updateBoardFromSchematic()

		XCTAssertEqual(report.missingFootprints, ["R1"])
		XCTAssertEqual(report.extraFootprints, ["J1"])
		XCTAssertFalse(report.isClean)
	}

	func testUpdateBoardReportsAPinWithNoMatchingPad() {
		var design = wiredDesign()
		design.board.footprints[1] = Footprint(spec: .init(kind: .soic, pins: 4), reference: "U1", at: .zero)
		let report = design.updateBoardFromSchematic()

		XCTAssertEqual(report.missingPins, ["U1.7"])
		XCTAssertEqual(report.assigned, 1)
	}

	func testUpdateBoardReusesAnExistingNetOfTheSameName() {
		var design = wiredDesign()
		design.schematic.labels = [NetLabel(at: design.schematic.wires[0].start, text: "GND")]
		let before = design.nets.count
		let report = design.updateBoardFromSchematic()

		XCTAssertEqual(report.created, [])
		XCTAssertEqual(design.nets.count, before)
	}

	// MARK: Ratsnest

	func testRatsnestSpansWhatCopperDoesNot() {
		var design = wiredDesign()
		_ = design.updateBoardFromSchematic()

		let rats = design.board.ratsnest()
		XCTAssertEqual(rats.count, 1)

		let pads = [
			design.board.footprints[0].placedPads.first { $0.name == "2" }!.at,
			design.board.footprints[1].placedPads.first { $0.name == "7" }!.at,
		]
		XCTAssertEqual(Set([rats[0].from, rats[0].to]), Set(pads))

		design.board.traces = [
			Trace(start: pads[0], end: pads[1], width: .mm(0.25), layer: 0, net: rats[0].net),
		]
		XCTAssertEqual(design.board.ratsnest(), [])
	}

	func testRatsnestIgnoresPadsWithNoNetAndViaBridgedCopper() {
		var design = Design(board: Board(size: Size(width: .mm(50), height: .mm(40)), stack: .two))
		design.board.footprints = [
			Footprint(spec: .init(kind: .header, pins: 2), reference: "J1", at: Pt(x: .mm(10), y: .mm(10))),
		]
		XCTAssertEqual(design.board.ratsnest(), [])

		design.board.footprints[0].pads.modifyEach { pad in pad.net = 0 }
		XCTAssertEqual(design.board.ratsnest().count, 1)

		let pads = design.board.footprints[0].placedPads.map(\.at)
		design.board.traces = [
			Trace(start: pads[0], end: Pt(x: .mm(20), y: .mm(20)), width: .mm(0.25), layer: 0, net: 0),
			Trace(start: Pt(x: .mm(20), y: .mm(20)), end: pads[1], width: .mm(0.25), layer: 1, net: 0),
		]
		XCTAssertEqual(design.board.ratsnest().count, 1, "different layers need a via")

		design.board.vias = [
			Via(at: Pt(x: .mm(20), y: .mm(20)), drill: .mm(0.3), pad: .mm(0.6), from: 0, to: 1, net: 0),
		]
		XCTAssertEqual(design.board.ratsnest(), [])
	}

	// MARK: Document

	func testDesignRoundTripsThroughJSON() throws {
		var design = wiredDesign()
		_ = design.updateBoardFromSchematic()
		design.board.planes = [nil, nil]

		let data = try JSONEncoder().encode(design)
		XCTAssertEqual(try JSONDecoder().decode(Design.self, from: data), design)
		XCTAssertEqual(try Document.decode(data), design)
	}

	func testDecodeRejectsADocumentItCannotUse() {
		XCTAssertThrowsError(try Document.decode(Data("{}".utf8)))
		XCTAssertThrowsError(try Document.decode(Data(#"{"size":{"_width":0,"_height":0},"stack":2,"planes":[null,null],"traces":[],"vias":[],"holes":[],"footprints":[],"rules":{"clearance":0,"traceWidth":0,"viaDrill":0,"viaPad":0}}"#.utf8)))
	}

	func testDecodeRejectsALegacyBoardAtTheRoot() throws {
		let legacy = """
		{
			"size": { "_width": 50000000, "_height": 40000000 },
			"stack": 2,
			"planes": [null, null],
			"nets": [{ "id": 0, "name": "GND" }, { "id": 7, "name": "SDA" }],
			"traces": [],
			"vias": [],
			"holes": [],
			"footprints": [],
			"rules": { "clearance": 200000, "traceWidth": 250000, "viaDrill": 300000, "viaPad": 600000 }
		}
		"""
		let data = Data(legacy.utf8)

		XCTAssertThrowsError(try Document.decode(data))
	}

	// MARK: Rendering

	@MainActor
	func testSchematicCanvasRendersAPopulatedSheetWithoutFailing() throws {
		var design = wiredDesign()
		design.schematic.symbols.append(contentsOf: [
			Symbol(spec: .init(kind: .capacitor), reference: "C1", at: Pt(x: .mm(20), y: .mm(30))),
			Symbol(spec: .init(kind: .inductor), reference: "L1", at: Pt(x: .mm(40), y: .mm(30))),
			Symbol(spec: .init(kind: .diode), reference: "D1", at: Pt(x: .mm(60), y: .mm(30))),
			Symbol(spec: .init(kind: .transistor), reference: "Q1", at: Pt(x: .mm(80), y: .mm(30))),
			Symbol(spec: .init(kind: .ground), reference: "#PWR1", at: Pt(x: .mm(20), y: .mm(50))),
			Symbol(spec: .init(kind: .power), reference: "#PWR2", at: Pt(x: .mm(40), y: .mm(50))),
		])
		design.schematic.wires.append(Wire(start: Pt(x: .mm(20), y: .mm(50)), end: Pt(x: .mm(40), y: .mm(50))))

		let view = SchematicView(design: .constant(design), state: .constant(SchematicState()))
		let renderer = ImageRenderer(
			content: SwiftUI.Canvas { ctx, size in view.render(in: ctx, size: size) }
				.frame(width: 640.0, height: 480.0)
		)
		XCTAssertNotNil(renderer.nsImage)
	}
}
