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

	func testAPinIsNamedOnlyWhenTheNameSaysMoreThanItsNumber() {
		XCTAssertFalse(Symbol.resistor().pins.contains(where: \.isNamed))
		XCTAssertFalse(Symbol.ic(pins: 8).pins.contains(where: \.isNamed))
		XCTAssertEqual(Symbol.diode().pins.filter(\.isNamed).map(\.name), ["A", "K"])
		XCTAssertEqual(Symbol.transistor().pins.filter(\.isNamed).map(\.name), ["B", "E", "C"])
	}

	func testPinNamesWidenTheICTheyAreWrittenInsideAndNumbersDoNot() {
		// Nothing is written inside a plainly numbered IC, so it keeps its size
		XCTAssertEqual(Symbol.ic(pins: 8).body.size.width, .mm(12.7))
		XCTAssertEqual(Symbol.ic(pins: 64).body.size.width, .mm(12.7))

		// PRESET ENABLE and BINARY/DECADE need more room than Q1 and CLOCK2
		XCTAssertGreaterThan(
			Component.cd4029.makeSymbol().body.size.width,
			Component.cd4013.makeSymbol().body.size.width
		)
		XCTAssertEqual(Component.cd4029.makeSymbol().body.size.width % .mm(2.54), 0)
	}

	func testEveryICIsWideEnoughToWriteItsPinNamesBetweenItsLegs() {
		for component in Component.allCases where component.symbolKind == .ic {
			let symbol = component.makeSymbol()
			let half = symbol.body.size.width / 2
			// The columns start at the body edge each leg leaves from
			var leftEnd = -half
			var rightStart = half

			for pin in symbol.pins where pin.isNamed {
				let reach = PinText.inset + PinText.width(pin.name)
				if pin.direction == .r180 {
					XCTAssertEqual(pin.root.x, -half, component.name)
					leftEnd = max(leftEnd, pin.root.x + reach)
				} else {
					XCTAssertEqual(pin.root.x, half, component.name)
					rightStart = min(rightStart, pin.root.x - reach)
				}
			}
			XCTAssertLessThan(leftEnd, half, component.name)
			XCTAssertGreaterThan(rightStart, -half, component.name)
			// And a pitch of clear air is left down the middle
			XCTAssertGreaterThanOrEqual(rightStart - leftEnd, .mm(2.54), component.name)
		}
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

	// MARK: Placing a part on both sides

	func testPlacingASymbolStandsItsFootprintOnTheBoard() {
		var design = Design()
		let ref = design.place(Symbol.Spec(kind: .resistor, value: "10k"), at: Pt(x: .mm(50), y: .mm(50)))

		XCTAssertEqual(ref, .symbol(0))
		XCTAssertEqual(design.schematic.symbols.map(\.reference), ["R1"])
		XCTAssertEqual(design.board.footprints.map(\.reference), ["R1"])
		XCTAssertEqual(design.schematic.symbols[0].at, Pt(x: .mm(50), y: .mm(50)))
		XCTAssertEqual(design.board.footprints[0].pads.map(\.name), ["1", "2"])
	}

	func testPlacingAFootprintDrawsItsSymbolOnTheSheet() {
		var design = Design()
		let ref = design.place(Footprint.Spec(kind: .soic, pins: 8), at: Pt(x: .mm(20), y: .mm(20)))

		XCTAssertEqual(ref, .footprint(0))
		XCTAssertEqual(design.board.footprints.map(\.reference), ["U1"])
		XCTAssertEqual(design.schematic.symbols.map(\.reference), ["U1"])
		XCTAssertEqual(design.board.footprints[0].at, Pt(x: .mm(20), y: .mm(20)))
		XCTAssertEqual(design.schematic.symbols[0].kind, .ic)
		XCTAssertEqual(design.schematic.symbols[0].pins.count, 8)
	}

	func testAPowerFlagStandsOnTheSheetAlone() {
		var design = Design()
		design.place(Symbol.Spec(kind: .ground), at: .zero)
		design.place(Symbol.Spec(kind: .power), at: Pt(x: .mm(10), y: 0))

		XCTAssertEqual(design.schematic.symbols.count, 2)
		XCTAssertTrue(design.board.footprints.isEmpty)
	}

	func testADesignatorIsFreeOnBothHalvesBeforeItIsUsed() {
		var design = Design()
		design.board.footprints = [
			Footprint(spec: .init(kind: .chip), reference: "R1", at: Pt(x: .mm(80), y: .mm(140))),
		]
		design.place(Symbol.Spec(kind: .resistor), at: .zero)

		XCTAssertEqual(design.schematic.symbols.map(\.reference), ["R2"])
		XCTAssertEqual(design.board.footprints.map(\.reference), ["R1", "R2"])
	}

	func testAPairedPartNeedsNoMatchingUpAfterwards() {
		var design = Design()
		design.place(Symbol.Spec(component: .ad823), at: Pt(x: .mm(200), y: .mm(150)))
		design.place(Footprint.Spec(kind: .chip), at: Pt(x: .mm(60), y: .mm(100)))

		let from = design.schematic.symbols[0].placedPins[0].at
		let to = design.schematic.symbols[1].placedPins[0].at
		design.schematic.wires = [Wire(start: from, end: to)]
		design.schematic.labels = [NetLabel(at: from, text: "OUT")]

		let report = design.updateBoardFromSchematic()
		XCTAssertTrue(report.isClean)
		XCTAssertGreaterThanOrEqual(report.assigned, 2)
	}

	func testAParkedPartCoversNothingAlreadyThere() {
		var design = Design()
		for index in 0 ..< 6 {
			design.place(Symbol.Spec(kind: .ic, pins: 8), at: Pt(x: .mm(20.0 + Double(index) * 40.0), y: .mm(180)))
			design.place(Footprint.Spec(kind: .header, pins: 3), at: Pt(x: .mm(90), y: .mm(20.0 + Double(index) * 20.0)))
		}

		assertNothingOverlaps(design.board.footprints.map(\.placedExtent), inside: design.board.bounds)
		assertNothingOverlaps(
			design.schematic.symbols.filter { $0.kind == .ic }.map(\.placedExtent),
			inside: design.schematic.bounds
		)
	}

	func testAParkedSymbolKeepsClearOfAWireAlreadyDrawn() {
		var design = Design()
		let wire = Wire(
			start: Pt(x: 0, y: .mm(12)),
			end: Pt(x: design.schematic.size.width, y: .mm(12))
		)
		design.schematic.wires = [wire]
		design.place(Footprint.Spec(kind: .soic, pins: 8), at: Pt(x: .mm(20), y: .mm(20)))

		let parked = design.schematic.symbols[0].placedExtent
		XCTAssertFalse(parked.intersects(Rect(from: wire.start, to: wire.end)))
		// Nothing has wired itself into the net the wire already carries
		XCTAssertEqual(Netlist(design.schematic).group(at: wire.start)?.nodes, [])
	}

	func testEveryPackagePairsWithASymbolThatHasAPadForEveryPin() {
		for kind in Symbol.Kind.allCases {
			let spec = Symbol.Spec(kind: kind, pins: 9)
			guard let package = spec.footprint else {
				XCTAssertTrue(kind.isPower, kind.name)
				continue
			}
			let symbol = Symbol(spec: spec, reference: "X1", at: .zero)
			let footprint = Footprint(spec: package, reference: "X1", at: .zero)
			XCTAssertTrue(
				Set(symbol.pins.map(\.number)).isSubset(of: Set(footprint.pads.map(\.name))),
				kind.name
			)
		}

		for kind in Footprint.Kind.allCases {
			let spec = Footprint.Spec(kind: kind, pins: 10, rows: 2)
			let footprint = Footprint(spec: spec, reference: "X1", at: .zero)
			let symbol = Symbol(spec: spec.symbol, reference: "X1", at: .zero)
			XCTAssertEqual(
				Set(symbol.pins.map(\.number)),
				Set(footprint.pads.map(\.name)),
				kind.name
			)
		}

		for component in Component.allCases {
			XCTAssertEqual(Symbol.Spec(component: component).footprint?.component, component, component.name)
			XCTAssertEqual(Footprint.Spec(component: component).symbol.component, component, component.name)
		}
	}

	private func assertNothingOverlaps(_ extents: [Rect], inside bounds: Rect) {
		for (index, extent) in extents.enumerated() {
			XCTAssertTrue(bounds.contains(extent.origin))
			XCTAssertTrue(bounds.contains(Pt(x: extent.maxX, y: extent.maxY)))
			for other in extents[(index + 1)...] {
				XCTAssertFalse(extent.intersects(other))
			}
		}
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

	@MainActor
	func testPinTextRendersAtEveryRotationOnceTheSheetIsZoomedIn() {
		var design = Design(board: Board(size: Size(width: .mm(50), height: .mm(40)), stack: .two))
		for (index, rotation) in Rotation.allCases.enumerated() {
			design.schematic.symbols.append(modifying(
				Symbol(
					spec: .init(component: .cd4013),
					reference: "U\(index + 1)",
					at: Pt(x: .mm(Double(30 + index * 40)), y: .mm(40))
				)
			) { symbol in
				symbol.rotation = rotation
				symbol.mirrored = rotation == .r180
			})
		}
		// A transistor writes its names beside the legs, having no room inside
		design.schematic.symbols.append(
			Symbol(spec: .init(kind: .transistor), reference: "Q1", at: Pt(x: .mm(20), y: .mm(15)))
		)

		var state = SchematicState()
		state.viewport.magnification = 8.0

		let view = SchematicView(design: .constant(design), state: .constant(state))
		let renderer = ImageRenderer(
			content: SwiftUI.Canvas { ctx, size in view.render(in: ctx, size: size) }
				.frame(width: 640.0, height: 480.0)
		)
		XCTAssertNotNil(renderer.nsImage)
	}
}
