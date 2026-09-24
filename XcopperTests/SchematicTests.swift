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

	private func wire(_ ax: µm, _ ay: µm, _ bx: µm, _ by: µm) -> Wire {
		Wire(start: Point(x: ax, y: ay), end: Point(x: bx, y: by))
	}

	func testATJunctionConnectsButACrossingDoesNot() {
		var schematic = Board()
		schematic.wires = [
			wire(0, 0, 10 * .mm, 0),
			wire(5 * .mm, 0, 5 * .mm, 10 * .mm),
			wire(0, 20 * .mm, 10 * .mm, 20 * .mm),
			wire(5 * .mm, 15 * .mm, 5 * .mm, 25 * .mm),
		]
		let netlist = Netlist(schematic)

		XCTAssertEqual(
			netlist.group(at: Point(x: 0, y: 0))?.points,
			netlist.group(at: Point(x: 5 * .mm, y: 10 * .mm))?.points
		)
		XCTAssertNotEqual(
			netlist.group(at: Point(x: 0, y: 20 * .mm))?.points,
			netlist.group(at: Point(x: 5 * .mm, y: 15 * .mm))?.points
		)
	}

	func testJunctionDotsAppearOnlyWhereThreeConductorsMeet() {
		var schematic = Board()
		schematic.wires = [wire(0, 0, 10 * .mm, 0), wire(5 * .mm, 0, 5 * .mm, 10 * .mm)]
		XCTAssertEqual(schematic.junctions, [Point(x: 5 * .mm, y: 0)])

		schematic.wires = [wire(0, 0, 5 * .mm, 0), wire(5 * .mm, 0, 10 * .mm, 0)]
		XCTAssertEqual(schematic.junctions, [])
	}

	func testAPinLabelNamesItsWire() {
		var schematic = Board()
		schematic.footprints = [Footprint(symbol: .init(kind: .resistor), reference: "R1", at: .zero)]
		let at = schematic.footprints[0].symbol.placedPins[0].at
		let end = at + Point(x: -10 * .mm, y: 0)
		schematic.wires = [Wire(start: at, end: end)]
		XCTAssertNil(Netlist(schematic).name(at: end))
		schematic.footprints[0].symbol.pins[0].netLabel = "SDA"
		XCTAssertEqual(Netlist(schematic).name(at: end), "SDA")
	}

	func testAGroundPinLabelNamesItsNet() {
		var schematic = Board()
		schematic.footprints = [Footprint(symbol: .init(kind: .resistor), reference: "R1", at: .zero)]
		schematic.footprints[0].symbol.pins[0].netLabel = "GND"
		XCTAssertEqual(Netlist(schematic).name(at: schematic.footprints[0].symbol.placedPins[0].at), "GND")
	}

	func testPinsOnTheSameWireLandInOneGroup() {
		var schematic = Board()
		schematic.footprints = [
			Footprint(symbol: .init(kind: .resistor), reference: "R1", at: .zero),
			Footprint(symbol: .init(kind: .resistor), reference: "R2", at: Point(x: 20 * .mm, y: 0)),
		]
		let right = schematic.footprints[0].symbol.placedPins[1].at
		let left = schematic.footprints[1].symbol.placedPins[0].at
		schematic.wires = [Wire(start: right, end: left)]

		let group = Netlist(schematic).group(at: right)
		XCTAssertEqual(group?.nodes, [.init(symbol: 0, pin: 1), .init(symbol: 1, pin: 0)])
	}

	func testOrthogonalSnapPicksTheDominantAxis() {
		let origin = Point.zero
		XCTAssertEqual(snapped90(from: origin, to: Point(x: 10 * .mm, y: 2 * .mm)), Point(x: 10 * .mm, y: 0))
		XCTAssertEqual(snapped90(from: origin, to: Point(x: 2 * .mm, y: 10 * .mm)), Point(x: 0, y: 10 * .mm))
		XCTAssertEqual(snapped90(from: origin, to: Point(x: 5 * .mm, y: 5 * .mm)), Point(x: 5 * .mm, y: 0))
	}

	func testSymbolRotationAndMirroringPlacePinsAbsolutely() {
		let at = Point(x: 10 * .mm, y: 20 * .mm)
		var symbol = Symbol(spec: .init(kind: .resistor), at: at)

		XCTAssertEqual(symbol.placedPins.map(\.at), [
			Point(x: 4_920, y: 20 * .mm),
			Point(x: 15_080, y: 20 * .mm),
		])
		XCTAssertEqual(symbol.placedPins.map(\.direction), [.r180, .r0])

		symbol.rotation = .r90
		XCTAssertEqual(symbol.placedPins.map(\.at), [
			Point(x: 10 * .mm, y: 14_920),
			Point(x: 10 * .mm, y: 25_080),
		])
		XCTAssertEqual(symbol.placedPins.map(\.direction), [.r270, .r90])

		symbol.rotation = .r0
		symbol.mirrored = true
		XCTAssertEqual(symbol.placedPins.map(\.at), [
			Point(x: 15_080, y: 20 * .mm),
			Point(x: 4_920, y: 20 * .mm),
		])
		XCTAssertEqual(symbol.placedPins.map(\.direction), [.r0, .r180])
	}

	func testPinLegsRunBackTowardsTheBody() {
		let symbol = Symbol(spec: .init(kind: .resistor), at: .zero)
		let pins = symbol.placedPins

		XCTAssertEqual(pins[0].root, Point(x: -2_540, y: 0))
		XCTAssertEqual(pins[1].root, Point(x: 2_540, y: 0))
	}

	func testICPinsRunDownTheLeftSideAndBackUpTheRight() {
		let symbol = Symbol(spec: .init(kind: .ic, pins: 8), at: .zero)
		XCTAssertEqual(symbol.pins.map(\.number), (1 ... 8).map { "\($0)" })
		XCTAssertEqual(symbol.pins[0].direction, .r180)
		XCTAssertEqual(symbol.pins[7].direction, .r0)

		XCTAssertEqual(symbol.pins[0].at.y, symbol.pins[7].at.y)
		XCTAssertEqual(symbol.pins[3].at.y, symbol.pins[4].at.y)
	}

	func testAPinIsNamedOnlyWhenTheNameSaysMoreThanItsNumber() {
		XCTAssertFalse(Symbol.resistor().pins.contains(where: \.isNamed))
		XCTAssertFalse(Symbol.ic(pins: 8).pins.contains(where: \.isNamed))
		XCTAssertEqual(Symbol.diode().pins.filter(\.isNamed).map(\.name), ["A", "K"])
		XCTAssertEqual(Symbol.transistor().pins.filter(\.isNamed).map(\.name), ["B", "E", "C"])
	}

	func testAChipTakesItsNetsFromAPassiveThatWritesNoPinNumbers() {
		var design = Design(board: Board(size: Size(width: 50 * .mm, height: 40 * .mm), stack: .classic))
		design.place(Symbol.Spec(kind: .capacitor), at: .zero)
		design.place(Symbol.Spec(kind: .resistor), at: Point(x: 20 * .mm, y: 0))

		let from = design.board.footprints[0].symbol.placedPins[1].at
		let to = design.board.footprints[1].symbol.placedPins[0].at
		design.board.wires = [Wire(start: from, end: to)]

		let report = design.updateBoardFromSchematic()
		XCTAssertEqual(report.assigned, 2)
		XCTAssertTrue(report.missingPins.isEmpty)
	}

	func testPinNamesWidenTheICTheyAreWrittenInsideAndNumbersDoNot() {
		XCTAssertEqual(Symbol.ic(pins: 8).body.size.width, 12_700)
		XCTAssertEqual(Symbol.ic(pins: 64).body.size.width, 12_700)

		XCTAssertGreaterThan(
			Component.cd4029.makeSymbol().body.size.width,
			Component.cd4013.makeSymbol().body.size.width
		)
		XCTAssertEqual(Component.cd4029.makeSymbol().body.size.width % (2_540), 0)
	}

	func testEveryICIsWideEnoughToWriteItsPinNamesBetweenItsLegs() {
		for component in Component.allCases where component.symbolKind == .ic {
			let symbol = component.makeSymbol()
			let half = symbol.body.size.width / 2
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
			XCTAssertGreaterThanOrEqual(rightStart - leftEnd, 2_540, component.name)
		}
	}

	func testHitTestAndRubberBandSelectionCoverEveryKind() {
		var schematic = Board()
		schematic.footprints = [Footprint(symbol: .init(kind: .resistor), reference: "R1", at: Point(x: 10 * .mm, y: 10 * .mm))]
		schematic.wires = [wire(0, 30 * .mm, 10 * .mm, 30 * .mm)]
		schematic.footprints[0].symbol.pins[0].netLabel = "CLK"

		XCTAssertEqual(schematic.schematicHitTest(at: Point(x: 10 * .mm, y: 10 * .mm), tolerance: 0), .symbol(0))
		XCTAssertEqual(schematic.schematicHitTest(at: Point(x: 8 * .mm, y: 30 * .mm), tolerance: 0), .wire(0))
		XCTAssertNil(schematic.schematicHitTest(at: Point(x: 60 * .mm, y: 60 * .mm), tolerance: 0))

		let all = Rect(from: .zero, to: Point(x: 50 * .mm, y: 50 * .mm))
		XCTAssertEqual(schematic.schematicRefs(in: all), [.symbol(0), .wire(0)])
	}

	func testSnapTargetUsesPinsWithOrWithoutLabels() {
		var schematic = Board()
		schematic.footprints = [Footprint(symbol: .init(kind: .resistor), reference: "R1", at: .zero)]
		schematic.footprints[0].symbol.pins[0].netLabel = "CLK"
		let anchor = schematic.footprints[0].symbol.placedPins[0].at
		let near = anchor + Point(x: -300, y: 0)
		XCTAssertEqual(schematic.snapTarget(near: near, radius: 800), anchor)
		schematic.footprints[0].symbol.pins[0].netLabel = nil
		XCTAssertEqual(schematic.snapTarget(near: near, radius: 800), anchor)
	}

	func testDuplicateOffsetsCopiesOfSymbols() {
		var schematic = Board()
		schematic.footprints = [Footprint(symbol: .init(kind: .resistor), reference: "R1", at: Point(x: 10 * .mm, y: 10 * .mm))]
		let created = schematic.duplicateSchematic([.symbol(0)], by: Point(x: 5 * .mm, y: 0))

		XCTAssertEqual(created, [.symbol(1)])
		XCTAssertEqual(schematic.footprints[1].symbol.at, Point(x: 15 * .mm, y: 10 * .mm))
	}

	func testMirroringASelectionFlipsAroundItsOwnCentre() {
		var schematic = Board()
		schematic.footprints = [
			Footprint(symbol: .init(kind: .resistor), reference: "R1", at: Point(x: 10 * .mm, y: 0)),
			Footprint(symbol: .init(kind: .resistor), reference: "R2", at: Point(x: 30 * .mm, y: 0)),
		]
		schematic.mirrorSchematic([.symbol(0), .symbol(1)])

		XCTAssertEqual(schematic.footprints[0].symbol.at.x, 30 * .mm)
		XCTAssertEqual(schematic.footprints[1].symbol.at.x, 10 * .mm)
		XCTAssertTrue(schematic.symbols.allSatisfy(\.mirrored))
	}

	func testPlacingASymbolStandsItsFootprintOnTheBoard() {
		var design = Design()
		let ref = design.place(Symbol.Spec(kind: .resistor, value: "10k"), at: Point(x: 50 * .mm, y: 50 * .mm))

		XCTAssertEqual(ref, .symbol(0))
		XCTAssertEqual(design.board.footprints.map(\.reference), ["R1"])
		XCTAssertEqual(design.board.footprints[0].symbol.at, Point(x: 50 * .mm, y: 50 * .mm))
		XCTAssertEqual(design.board.footprints[0].pads.map(\.name), ["1", "2"])
	}

	func testPlacingAFootprintDrawsItsSymbolOnTheSheet() {
		var design = Design()
		let ref = design.place(Footprint.Spec(kind: .soic, pins: 8), at: Point(x: 20 * .mm, y: 20 * .mm))

		XCTAssertEqual(ref, .footprint(0))
		XCTAssertEqual(design.board.footprints.map(\.reference), ["U1"])
		XCTAssertEqual(design.board.footprints[0].at, Point(x: 20 * .mm, y: 20 * .mm))
		XCTAssertEqual(design.board.footprints[0].symbolKind, .ic)
		XCTAssertEqual(design.board.footprints[0].symbol.pins.count, 8)
	}

	func testACapacitorChipIsDrawnAndDesignatedAsOneRatherThanAsAResistor() {
		var design = Design()
		design.place(Footprint.Spec(kind: .chip, chip: .c1206, device: .capacitor), at: .zero)
		design.place(Footprint.Spec(kind: .chip, chip: .c1206), at: Point(x: 10 * .mm, y: 0))

		XCTAssertEqual(design.board.footprints.map(\.reference), ["C1", "R1"])
		XCTAssertEqual(design.board.footprints.map(\.symbolKind), [.capacitor, .resistor])
	}

	func testACapacitorAskedForFromTheSheetComesBackToAChipOfItsOwnKind() {
		let package = Symbol.Spec(kind: .capacitor).footprint
		XCTAssertEqual(package, Footprint.Spec(kind: .chip, chip: .c1206, device: .capacitor))
		XCTAssertEqual(package.symbol.kind, .capacitor)
		XCTAssertEqual(package.referencePrefix, "C")
	}

	func testPowerLabelsBelongToPinsWithoutCreatingExtraParts() {
		var design = Design()
		design.place(Symbol.Spec(kind: .resistor), at: .zero)
		design.board.footprints[0].symbol.pins[0].netLabel = "GND"
		design.board.footprints[0].symbol.pins[1].netLabel = "VCC"
		XCTAssertEqual(design.board.symbols.count, 1)
		XCTAssertEqual(design.board.footprints.count, 1)
	}

	func testADesignatorIsFreeOnBothHalvesBeforeItIsUsed() {
		var design = Design()
		design.board.footprints = [
			Footprint(spec: .init(kind: .chip), reference: "R1", at: Point(x: 80 * .mm, y: 140 * .mm)),
		]
		design.place(Symbol.Spec(kind: .resistor), at: .zero)

		XCTAssertEqual(design.board.footprints.map(\.reference), ["R1", "R2"])
	}

	func testAPairedPartNeedsNoMatchingUpAfterwards() {
		var design = Design()
		design.place(Symbol.Spec(component: .ad823), at: Point(x: 200 * .mm, y: 150 * .mm))
		design.place(Footprint.Spec(kind: .chip), at: Point(x: 60 * .mm, y: 100 * .mm))

		let from = design.board.footprints[0].symbol.placedPins[0].at
		let to = design.board.footprints[1].symbol.placedPins[0].at
		design.board.wires = [Wire(start: from, end: to)]
		design.board.footprints[0].symbol.pins[0].netLabel = "OUT"

		let report = design.updateBoardFromSchematic()
		XCTAssertTrue(report.isClean)
		XCTAssertGreaterThanOrEqual(report.assigned, 2)
	}

	func testAParkedPartCoversNothingAlreadyThere() {
		var design = Design()
		for index in 0 ..< 6 {
			design.place(Symbol.Spec(kind: .ic, pins: 8), at: Point(x: (20 + index * 40) * .mm, y: 180 * .mm))
			design.place(Footprint.Spec(kind: .header, pins: 3), at: Point(x: 90 * .mm, y: (20 + index * 20) * .mm))
		}

		assertNothingOverlaps(design.board.footprints.map(\.placedExtent), inside: design.board.bounds)
		assertNothingOverlaps(
			design.board.footprints.filter { $0.symbolKind == .ic }.map(\.symbol.placedExtent),
			inside: design.board.sheetBounds
		)
	}

	func testAParkedSymbolKeepsClearOfAWireAlreadyDrawn() {
		var design = Design()
		let wire = Wire(
			start: Point(x: 0, y: 12 * .mm),
			end: Point(x: design.board.sheetSize.width, y: 12 * .mm)
		)
		design.board.wires = [wire]
		design.place(Footprint.Spec(kind: .soic, pins: 8), at: Point(x: 20 * .mm, y: 20 * .mm))

		let parked = design.board.footprints[0].symbol.placedExtent
		XCTAssertFalse(parked.intersects(Rect(from: wire.start, to: wire.end)))
		XCTAssertEqual(Netlist(design.board).group(at: wire.start)?.nodes, [])
	}

	private func assertNothingOverlaps(_ extents: [Rect], inside bounds: Rect) {
		for (index, extent) in extents.enumerated() {
			XCTAssertTrue(bounds.contains(extent.origin))
			XCTAssertTrue(bounds.contains(Point(x: extent.maxX, y: extent.maxY)))
			for other in extents[(index + 1)...] {
				XCTAssertFalse(extent.intersects(other))
			}
		}
	}

	@MainActor
	func testResizingTheSheetKeepsTheDrawingAndIsUndoable() {
		var design = Design()
		design.board.wires = [wire(10 * .mm, 10 * .mm, 40 * .mm, 10 * .mm)]
		design.board.footprints = [Footprint(symbol: .init(kind: .resistor), reference: "R1", at: .zero)]
		design.board.footprints[0].symbol.pins[0].netLabel = "IN"
		let harness = EditorHarness(design: design)
		harness.editor.mode = .schematic
		harness.schematic.selection = [.wire(0)]
		let size = Size(width: 420 * .mm, height: 297 * .mm)

		harness.perform { $0.design.board.sheetSize = size }

		XCTAssertEqual(harness.design.board.sheetSize, size)
		XCTAssertEqual(harness.design.board.sheetBounds, Rect(origin: .zero, size: size))
		XCTAssertEqual(harness.design.board.wires, design.board.wires)
		XCTAssertEqual(harness.design.board.symbols, design.board.symbols)
		XCTAssertEqual(harness.design.board.footprints, design.board.footprints)
		XCTAssertEqual(harness.design.board.size, design.board.size)

		harness.undo.undo()
		XCTAssertEqual(harness.design, design)
	}

	func testASymbolShowsItsFootprintAndAFootprintItsSymbol() {
		var design = Design()
		design.place(Symbol.Spec(kind: .resistor), at: Point(x: 40 * .mm, y: 40 * .mm))
		design.place(Footprint.Spec(kind: .soic, pins: 8), at: Point(x: 20 * .mm, y: 20 * .mm))

		XCTAssertEqual(design.board.footprints.map(\.reference), ["R1", "U1"])
		XCTAssertEqual(design.footprints(for: [.symbol(0)]), [.footprint(0)])
		XCTAssertEqual(design.symbols(for: [.footprint(1)]), [.symbol(1)])
		XCTAssertEqual(design.footprints(for: [.symbol(0), .symbol(1)]), [.footprint(0), .footprint(1)])
	}

	func testOnlyAPartHasAnotherHalfToShow() {
		var design = Design()
		design.board.wires = [wire(0, 0, 10 * .mm, 0)]
		design.board.traces = [
			Trace(start: .zero, end: Point(x: 10 * .mm, y: 0), width: 400, layer: 0, net: nil),
		]

		XCTAssertTrue(design.board.footprints.isEmpty)
		XCTAssertTrue(design.footprints(for: [.wire(0)]).isEmpty)
		XCTAssertTrue(design.symbols(for: [.trace(0)]).isEmpty)
		XCTAssertTrue(design.footprints(for: []).isEmpty)
	}

	func testAPartWhoseOtherHalfHasGoneHasNothingToShow() {
		var design = Design()
		design.place(Symbol.Spec(kind: .resistor), at: Point(x: 40 * .mm, y: 40 * .mm))
		design.board.footprints = []

		XCTAssertTrue(design.footprints(for: [.symbol(0)]).isEmpty)
	}

	func testRevealingAPointScrollsItIntoTheMiddleOfTheView() {
		var viewport = Viewport()
		viewport.size = CGSize(width: 400.0, height: 300.0)
		viewport.magnification = 4.0
		let sheet = Size(width: 100 * .mm, height: 80 * .mm)

		viewport.revealPending(in: sheet)
		XCTAssertEqual(viewport.scrollPosition.point, .zero)

		viewport.reveal(Point(x: 50 * .mm, y: 40 * .mm))
		viewport.revealPending(in: sheet)

		XCTAssertNil(viewport.pending)
		XCTAssertEqual(viewport.scrollPosition.point?.x ?? 0.0, 24.0, accuracy: 0.001)
		XCTAssertEqual(viewport.scrollPosition.point?.y ?? 0.0, 34.0, accuracy: 0.001)
	}

	func testARevealNeverScrollsPastTheEndsOfTheDocument() {
		var viewport = Viewport()
		viewport.size = CGSize(width: 400.0, height: 300.0)
		viewport.magnification = 4.0
		let sheet = Size(width: 100 * .mm, height: 80 * .mm)

		viewport.reveal(Point(x: 0, y: 0))
		viewport.revealPending(in: sheet)
		XCTAssertEqual(viewport.scrollPosition.point, .zero)

		viewport.reveal(Point(x: sheet.width, y: sheet.height))
		viewport.revealPending(in: sheet)
		XCTAssertEqual(viewport.scrollPosition.point?.x ?? 0.0, 48.0, accuracy: 0.001)
		XCTAssertEqual(viewport.scrollPosition.point?.y ?? 0.0, 68.0, accuracy: 0.001)
	}

	func testACanvasOfNoSizeYetKeepsTheRevealItWasAskedFor() {
		var viewport = Viewport()
		viewport.reveal(Point(x: 50 * .mm, y: 40 * .mm))
		viewport.revealPending(in: Size(width: 100 * .mm, height: 80 * .mm))

		XCTAssertEqual(viewport.pending, Point(x: 50 * .mm, y: 40 * .mm))
		XCTAssertEqual(viewport.scrollPosition.point, .zero)
	}

	private func wiredDesign() -> Design {
		var design = Design(board: Board(size: Size(width: 50 * .mm, height: 40 * .mm), stack: .classic))
		design.board.footprints = [
			Footprint(spec: .init(kind: .chip, chip: .c0603), reference: "R1", at: Point(x: 10 * .mm, y: 10 * .mm)),
			Footprint(spec: .init(kind: .soic, pins: 8), reference: "U1", at: Point(x: 30 * .mm, y: 20 * .mm)),
		]
		design.board.footprints[1].symbol.at = Point(x: 40 * .mm, y: 0)
		let from = design.board.footprints[0].symbol.placedPins[1].at
		let to = design.board.footprints[1].symbol.placedPins[6].at
		design.board.wires = [Wire(start: from, end: to)]
		design.board.footprints[0].symbol.pins[1].netLabel = "SDA"

		return design
	}

	func testUpdateBoardAssignsPadNetsByFootprintIndexAndPinNumber() {
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

	func testUpdateBoardReportsAPinWithNoMatchingPad() {
		var design = wiredDesign()
		design.board.footprints[1].pads.removeAll { $0.name == "7" }
		let report = design.updateBoardFromSchematic()

		XCTAssertEqual(report.missingPins, ["U1.7"])
		XCTAssertEqual(report.assigned, 1)
	}

	func testUpdateBoardReusesAnExistingNetOfTheSameName() {
		var design = wiredDesign()
		design.board.footprints[0].symbol.pins[1].netLabel = "GND"
		let before = design.nets.count
		let report = design.updateBoardFromSchematic()

		XCTAssertEqual(report.created, [])
		XCTAssertEqual(design.nets.count, before)
	}

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
			Trace(start: pads[0], end: pads[1], width: 250, layer: 0, net: rats[0].net),
		]
		XCTAssertEqual(design.board.ratsnest(), [])
	}

	func testRatsnestIgnoresPadsWithNoNetAndViaBridgedCopper() {
		var design = Design(board: Board(size: Size(width: 50 * .mm, height: 40 * .mm), stack: .classic))
		design.board.footprints = [
			Footprint(spec: .init(kind: .header, pins: 2), reference: "J1", at: Point(x: 10 * .mm, y: 10 * .mm)),
		]
		XCTAssertEqual(design.board.ratsnest(), [])

		design.board.footprints[0].pads.modifyEach { pad in pad.net = 0 }
		XCTAssertEqual(design.board.ratsnest().count, 1)

		let pads = design.board.footprints[0].placedPads.map(\.at)
		design.board.traces = [
			Trace(start: pads[0], end: Point(x: 20 * .mm, y: 20 * .mm), width: 250, layer: 0, net: 0),
			Trace(start: Point(x: 20 * .mm, y: 20 * .mm), end: pads[1], width: 250, layer: 1, net: 0),
		]
		XCTAssertEqual(design.board.ratsnest().count, 1, "different layers need a via")

		design.board.vias = [
			Via(at: Point(x: 20 * .mm, y: 20 * .mm), net: 0),
		]
		XCTAssertEqual(design.board.ratsnest(), [])
	}

	func testAPlaneJoinsWhatIsDrilledThroughIt() {
		var design = Design(board: Board(size: Size(width: 50 * .mm, height: 40 * .mm), stack: .digital))
		design.board.footprints = [
			Footprint(spec: .init(kind: .header, pins: 2), reference: "J1", at: Point(x: 10 * .mm, y: 10 * .mm)),
			Footprint(spec: .init(kind: .header, pins: 2), reference: "J2", at: Point(x: 30 * .mm, y: 30 * .mm)),
		]
		design.board.footprints.modifyEach { footprint in
			footprint.pads.modifyEach { pad in pad.net = 0 }
		}
		XCTAssertEqual(design.board.ratsnest().count, 3)
		XCTAssertEqual(design.board.ratsnest(planes: design.planes), [])

		design.board.footprints.modifyEach { footprint in
			footprint.pads.modifyEach { pad in pad.net = 2 }
		}
		XCTAssertEqual(design.board.ratsnest(planes: design.planes).count, 3, "VEE is no plane here")
	}

	func testAPlaneLeavesCopperItDoesNotReachAlone() {
		var design = Design(board: Board(size: Size(width: 50 * .mm, height: 40 * .mm), stack: .digital))
		design.board.footprints = [
			modifying(
				Footprint(spec: .init(kind: .chip), reference: "R1", at: Point(x: 10 * .mm, y: 10 * .mm))
			) { footprint in footprint.pads.modifyEach { pad in pad.net = 0 } },
			modifying(
				Footprint(spec: .init(kind: .chip), reference: "R2", at: Point(x: 30 * .mm, y: 30 * .mm))
			) { footprint in footprint.pads.modifyEach { pad in pad.net = 0 } },
		]
		XCTAssertEqual(design.board.ratsnest(planes: design.planes).count, 3)
	}

	func testDesignRoundTripsThroughJSON() throws {
		var design = wiredDesign()
		_ = design.updateBoardFromSchematic()

		let data = try JSONEncoder().encode(design)
		let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
		XCTAssertNil(object["schematic"])
		let board = try XCTUnwrap(object["board"] as? [String: Any])
		let footprints = try XCTUnwrap(board["footprints"] as? [[String: Any]])
		for footprint in footprints {
			let symbol = try XCTUnwrap(footprint["symbol"] as? [String: Any])
			for key in ["reference", "value", "component", "kind"] { XCTAssertNil(symbol[key]) }
		}
		XCTAssertEqual(try JSONDecoder().decode(Design.self, from: data), design)
		XCTAssertEqual(try Document.decode(data), design)
	}

	func testLegacySchematicMigrationPreservesPairsAndUnmatchedParts() throws {
		var original = wiredDesign()
		original.board.footprints[0].value = "#GAIN"
		original.parameters[0].defaultValue = "10K"
		var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Document(design: original).encoded()) as? [String: Any])
		var board = try XCTUnwrap(object["board"] as? [String: Any])
		var footprints = try XCTUnwrap(board["footprints"] as? [[String: Any]])
		var symbols: [[String: Any]] = []
		for index in footprints.indices {
			var symbol = try XCTUnwrap(footprints[index].removeValue(forKey: "symbol") as? [String: Any])
			symbol["reference"] = footprints[index]["reference"]
			symbol["value"] = footprints[index]["value"]
			symbol["kind"] = original.board.footprints[index].symbolKind.rawValue
			symbols.append(symbol)
		}
		footprints[0]["value"] = ""
		var unpaired = symbols[0]
		unpaired["reference"] = "R2"
		unpaired["value"] = "22K"
		symbols.append(unpaired)
		var extra = footprints[0]
		extra["reference"] = "R3"
		footprints.append(extra)
		board["footprints"] = footprints
		object["schematic"] = [
			"size": try XCTUnwrap(board.removeValue(forKey: "sheetSize")),
			"wires": try XCTUnwrap(board.removeValue(forKey: "wires")),
			"symbols": Array(symbols.reversed()),
		]
		object["board"] = board

		let migrated = try Document.decode(JSONSerialization.data(withJSONObject: object))
		XCTAssertEqual(migrated.parameters, original.parameters)
		XCTAssertEqual(migrated.board.sheetSize, original.board.sheetSize)
		XCTAssertEqual(migrated.board.wires, original.board.wires)
		XCTAssertEqual(migrated.board.footprints.map(\.reference), ["R1", "U1", "R3", "R2"])
		XCTAssertEqual(Array(migrated.board.footprints.prefix(2)), original.board.footprints)
		XCTAssertEqual(migrated.board.footprints[3].value, "22K")
		XCTAssertEqual(migrated.board.footprints[3].symbol, original.board.footprints[0].symbol)
		XCTAssertNotEqual(migrated.board.footprints[2].symbol.at, .zero)
		XCTAssertEqual(try Document.decode(Document(design: migrated).encoded()), migrated)
	}

	func testPinAssignmentsStayWithTheirFootprintsWhenReferencesMatch() {
		var design = wiredDesign()
		design.board.footprints[1].reference = design.board.footprints[0].reference
		design.board.wires = []
		design.board.footprints[0].symbol.pins[1].netLabel = "FIRST"
		design.board.footprints[1].symbol.pins[6].netLabel = "SECOND"
		_ = design.updateBoardFromSchematic()
		XCTAssertEqual(design.net(design.board.footprints[0].pads[1].net)?.name, "FIRST")
		XCTAssertEqual(design.net(design.board.footprints[1].pads[6].net)?.name, "SECOND")
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
}
