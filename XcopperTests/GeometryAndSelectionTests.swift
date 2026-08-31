import SwiftUI
import XCTest
@testable import Xcopper

final class GeometryAndSelectionTests: XCTestCase {

	private func board(_ stack: Stack = .four) -> Board {
		Board(size: Size(width: .mm(50), height: .mm(40)), stack: stack)
	}

	private func trace(from start: Pt, to end: Pt, layer: Int = 0) -> Trace {
		Trace(start: start, end: end, width: .mm(0.3), layer: layer, net: nil)
	}

	/// The sharpest corner the copper turns anywhere on the board, in eighths
	/// of a turn: none runs straight through, one is the 45 degree bend copper
	/// is drawn with and two squares the corner off. Asks the board the same
	/// question a move asks it, so these assertions cannot drift from the rule
	/// the drag actually enforces.
	private func sharpestTurn(_ board: Board) -> Int {
		var sharpest = 0
		for trace in board.traces {
			for point in [trace.start, trace.end] {
				let turn = board.turn(at: Junction(point: point, layer: trace.layer))
				sharpest = max(sharpest, turn ?? 0)
			}
		}
		return sharpest
	}

	func testSchematicIsTheFirstAndDefaultEditorMode() {
		XCTAssertEqual(Mode.allCases, [.schematic, .layout, .preview])
		XCTAssertEqual(Mode.schematic.shortcutCharacter, "1")
		XCTAssertEqual(Mode.layout.shortcutCharacter, "2")
		XCTAssertEqual(Mode.preview.shortcutCharacter, "3")
		XCTAssertEqual(EditorState().mode, .schematic)
	}

	func testNewDesignDefaultsToFourBySixInchesAndSixLayers() {
		let design = Design()
		XCTAssertEqual(design.board.size, Size(width: .inches(4), height: .inches(6)))
		XCTAssertEqual(design.board.stack, .six)
		XCTAssertEqual(design.board.planes, Array(repeating: nil, count: 6))
		XCTAssertEqual(design.nets.map(\.name), ["GND", "VCC", "VEE"])
		XCTAssertEqual(design.net(2)?.name, "VEE")
	}

	func testSnap45PicksNearestOctantAndProjectsOntoIt() {
		let origin = Pt.zero

		XCTAssertEqual(
			snapped45(from: origin, to: Pt(x: .mm(10), y: .mm(1))),
			Pt(x: .mm(10), y: 0)
		)
		XCTAssertEqual(
			snapped45(from: origin, to: Pt(x: .mm(1), y: .mm(10))),
			Pt(x: 0, y: .mm(10))
		)
		let diagonal = snapped45(from: origin, to: Pt(x: .mm(10), y: .mm(-8)))
		XCTAssertEqual(diagonal.x, -diagonal.y)
		XCTAssertEqual(diagonal.x, .mm(9))
		XCTAssertEqual(snapped45(from: origin, to: origin), origin)
	}

	func testCopperTurns45DegreesAtATimeOrCarriesStraightOn() {
		let east = Pt(x: 1, y: 0)

		XCTAssertEqual(east.turn(to: Pt(x: .mm(10), y: 0)), 0)
		XCTAssertEqual(east.turn(to: Pt(x: .mm(10), y: .mm(10))), 1)
		XCTAssertEqual(east.turn(to: Pt(x: 0, y: .mm(10))), 2)
		XCTAssertEqual(east.turn(to: Pt(x: .mm(-10), y: .mm(10))), 3)
		XCTAssertEqual(east.turn(to: Pt(x: .mm(-10), y: 0)), 4)

		XCTAssertTrue(east.bends(to: Pt(x: .mm(5), y: .mm(-5))))
		XCTAssertFalse(east.bends(to: Pt(x: 0, y: .mm(5))))
		XCTAssertFalse(east.bends(to: Pt(x: .mm(-5), y: .mm(5))))

		// A free angle is copper this has nothing to say about
		XCTAssertNil(east.turn(to: Pt(x: .mm(10), y: .mm(3))))
		XCTAssertTrue(east.bends(to: Pt(x: .mm(10), y: .mm(3))))
	}

	func testARouteChainingOnCopperWillNotSquareTheCorner() {
		let start = Pt.zero
		let east = Pt(x: 1, y: 0)

		// Straight on and either 45 degree turn are drawn as the pointer asks
		XCTAssertEqual(
			snapped45(from: start, to: Pt(x: .mm(10), y: 0), after: east),
			Pt(x: .mm(10), y: 0)
		)
		XCTAssertEqual(
			snapped45(from: start, to: Pt(x: .mm(10), y: .mm(9)), after: east),
			Pt(x: .mm(9.5), y: .mm(9.5))
		)

		// Square to the copper it chains off, the route swings back onto the
		// nearer of the two turns rather than drawing the right angle asked for
		XCTAssertEqual(
			snapped45(from: start, to: Pt(x: .mm(1), y: .mm(10)), after: east),
			Pt(x: .mm(5.5), y: .mm(5.5))
		)
		XCTAssertEqual(
			snapped45(from: start, to: Pt(x: .mm(1), y: .mm(-10)), after: east),
			Pt(x: .mm(5.5), y: .mm(-5.5))
		)

		// Behind the copper there is no gentle turn at all, so nothing is drawn
		XCTAssertEqual(snapped45(from: start, to: Pt(x: .mm(-10), y: .mm(1)), after: east), start)
	}

	func testGridSnapRoundsToNearestStepInBothDirections() {
		let grid = Nm.mm(0.25)
		XCTAssertEqual(Pt(x: .mm(0.3), y: .mm(-0.3)).snapped(to: grid), Pt(x: .mm(0.25), y: .mm(-0.25)))
		XCTAssertEqual(Pt(x: .mm(0.13), y: .mm(0.12)).snapped(to: grid), Pt(x: .mm(0.25), y: 0))
		XCTAssertEqual(Pt(x: 7, y: 7).snapped(to: 0), Pt(x: 7, y: 7))
	}

	func testSnapAndDisplayGridPresetsAreIndependent() {
		XCTAssertEqual(Nm.snapGrids, [.mil(5), .mil(10), .mil(25), .mil(50), .mil(100)])
		XCTAssertEqual(Nm.snapGrids.map(\.label), ["0.127", "0.254", "0.635", "1.27", "2.54"])
		XCTAssertEqual(Nm.sheetSnapGrids, [.mil(50), .mil(100)])
		XCTAssertEqual(Nm.displayGrids, [.mm(1.27), .mm(2.54)])
		XCTAssertEqual(LayoutState().snap, .mil(10))
		XCTAssertEqual(LayoutState().grid, .mm(1.27))
		XCTAssertEqual(SchematicState().snap, .mm(1.27))
		XCTAssertEqual(SchematicState().grid, .mm(1.27))
	}

	func testInchConversionPreservesBoardDimensions() {
		XCTAssertEqual(Nm.inches(1), .mm(25.4))
		XCTAssertEqual(Nm.mm(50.8).inches, 2.0, accuracy: 0.000_000_01)
	}

	func testSnapTargetPrefersTheNearestPadOnTheRoutedLayer() {
		var board = board()
		board.footprints = [Footprint(spec: .init(kind: .chip, chip: .c0805), reference: "R1", at: Pt(x: .mm(10), y: .mm(10)))]
		board.vias = [Via(at: Pt(x: .mm(20), y: .mm(20)), drill: .mm(0.3), pad: .mm(0.6), from: 0, to: 3, net: 1)]

		let pad = board.footprints[0].placedPads[0].at
		let near = Pt(x: pad.x + .mm(0.1), y: pad.y)
		XCTAssertEqual(board.snapTarget(near: near, layer: 0, radius: .mm(0.4))?.0, pad)

		XCTAssertNil(board.snapTarget(near: Pt(x: .mm(40), y: .mm(30)), layer: 0, radius: .mm(0.4)))

		let viaTarget = board.snapTarget(near: Pt(x: .mm(20.1), y: .mm(20)), layer: 2, radius: .mm(0.4))
		XCTAssertEqual(viaTarget?.0, Pt(x: .mm(20), y: .mm(20)))
		XCTAssertEqual(viaTarget?.1, 1)
	}

	func testHitTestRespectsLayerToleranceAndTopmostOrder() {
		var board = board()
		board.traces = [
			Trace(start: Pt(x: 0, y: .mm(5)), end: Pt(x: .mm(10), y: .mm(5)), width: .mm(0.25), layer: 0, net: nil),
			Trace(start: Pt(x: 0, y: .mm(9)), end: Pt(x: .mm(10), y: .mm(9)), width: .mm(0.25), layer: 1, net: nil),
		]
		let tolerance = Int.mm(0.05)

		XCTAssertEqual(board.hitTest(at: Pt(x: .mm(5), y: .mm(5)), layer: 0, tolerance: tolerance), .trace(0))
		XCTAssertNil(board.hitTest(at: Pt(x: .mm(5), y: .mm(5)), layer: 1, tolerance: tolerance))
		XCTAssertEqual(board.hitTest(at: Pt(x: .mm(5), y: .mm(9)), layer: 1, tolerance: tolerance), .trace(1))

		XCTAssertNotNil(board.hitTest(at: Pt(x: 0, y: .mm(5) + .mm(0.16)), layer: 0, tolerance: tolerance))
		XCTAssertNil(board.hitTest(at: Pt(x: 0, y: .mm(5) + .mm(0.3)), layer: 0, tolerance: tolerance))

		board.vias = [Via(at: Pt(x: .mm(5), y: .mm(5)), drill: .mm(0.3), pad: .mm(0.6), from: 0, to: 3, net: nil)]
		XCTAssertEqual(board.hitTest(at: Pt(x: .mm(5), y: .mm(5)), layer: 0, tolerance: tolerance), .via(0))
	}

	func testRubberBandSelectionIsLayerFilteredAndNeedsWhollyContainedTraces() {
		var board = board()
		board.traces = [
			Trace(start: Pt(x: .mm(1), y: .mm(1)), end: Pt(x: .mm(5), y: .mm(5)), width: .mm(0.25), layer: 0, net: nil),
			Trace(start: Pt(x: .mm(6), y: .mm(6)), end: Pt(x: .mm(30), y: .mm(30)), width: .mm(0.25), layer: 0, net: nil),
			Trace(start: Pt(x: .mm(2), y: .mm(2)), end: Pt(x: .mm(4), y: .mm(4)), width: .mm(0.25), layer: 2, net: nil),
		]
		board.holes = [Hole(at: Pt(x: .mm(3), y: .mm(3)), diameter: .mm(3.2))]

		let rect = Rect(from: Pt(x: 0, y: 0), to: Pt(x: .mm(10), y: .mm(10)))
		XCTAssertEqual(board.refs(in: rect, layer: 0), [.trace(0), .hole(0)])
		XCTAssertEqual(board.refs(in: rect, layer: 2), [.trace(2), .hole(0)])
	}

	func testHoldingCommandSelectsTheWholeRunATraceIsPartOf() {
		var board = board()
		board.traces = [
			Trace(start: Pt(x: .mm(5), y: .mm(10)), end: Pt(x: .mm(10), y: .mm(10)), width: .mm(0.3), layer: 0, net: nil),
			Trace(start: Pt(x: .mm(10), y: .mm(10)), end: Pt(x: .mm(15), y: .mm(15)), width: .mm(0.3), layer: 0, net: nil),
			Trace(start: Pt(x: .mm(15), y: .mm(15)), end: Pt(x: .mm(15), y: .mm(20)), width: .mm(0.3), layer: 0, net: nil),
			Trace(start: Pt(x: .mm(15), y: .mm(15)), end: Pt(x: .mm(25), y: .mm(15)), width: .mm(0.3), layer: 1, net: nil),
		]
		XCTAssertEqual(
			board.refs(at: Pt(x: .mm(7), y: .mm(10)), layer: 0, tolerance: 0, whole: true),
			[.trace(0), .trace(1), .trace(2)]
		)
		XCTAssertEqual(
			board.refs(at: Pt(x: .mm(20), y: .mm(15)), layer: 1, tolerance: 0, whole: true),
			[.trace(3)]
		)
		XCTAssertEqual(
			board.refs(at: Pt(x: .mm(40), y: .mm(30)), layer: 0, tolerance: 0, whole: true),
			[]
		)
	}

	func testARunStopsWhereCopperBranchesOrMeetsAPad() {
		var board = board()
		board.footprints = [
			Footprint(spec: .init(kind: .chip, chip: .c0805), reference: "R1", at: Pt(x: .mm(30), y: .mm(10))),
		]
		let pad = board.footprints[0].placedPads[0].at
		board.traces = [
			Trace(start: Pt(x: .mm(10), y: .mm(10)), end: Pt(x: .mm(20), y: .mm(10)), width: .mm(0.3), layer: 0, net: nil),
			Trace(start: Pt(x: .mm(20), y: .mm(10)), end: pad, width: .mm(0.3), layer: 0, net: nil),
			Trace(start: Pt(x: .mm(20), y: .mm(10)), end: Pt(x: .mm(20), y: .mm(5)), width: .mm(0.3), layer: 0, net: nil),
			Trace(start: pad, end: Pt(x: pad.x, y: .mm(20)), width: .mm(0.3), layer: 0, net: nil),
		]
		XCTAssertEqual(board.run(of: 0), [0])
		XCTAssertEqual(board.run(of: 1), [1])
		XCTAssertEqual(board.run(of: 3), [3])
	}

	func testSelectionTakesTheOneSegmentUnderThePointerOrInsideTheBand() {
		var board = board()
		board.traces = [
			trace(from: Pt(x: .mm(5), y: .mm(10)), to: Pt(x: .mm(10), y: .mm(10))),
			trace(from: Pt(x: .mm(10), y: .mm(10)), to: Pt(x: .mm(15), y: .mm(15))),
		]
		XCTAssertEqual(board.refs(at: Pt(x: .mm(7), y: .mm(10)), layer: 0, tolerance: 0), [.trace(0)])

		// The band takes a segment that fits inside it, run or no run
		let partial = Rect(from: Pt(x: 0, y: 0), to: Pt(x: .mm(12), y: .mm(12)))
		XCTAssertEqual(board.refs(in: partial, layer: 0), [.trace(0)])

		let clipped = Rect(from: Pt(x: 0, y: 0), to: Pt(x: .mm(8), y: .mm(12)))
		XCTAssertEqual(board.refs(in: clipped, layer: 0), [])
	}

	func testARubberBandTakesARunOnlyWhenItCoversAllOfIt() {
		var board = board()
		board.traces = [
			Trace(start: Pt(x: .mm(5), y: .mm(5)), end: Pt(x: .mm(10), y: .mm(5)), width: .mm(0.3), layer: 0, net: nil),
			Trace(start: Pt(x: .mm(10), y: .mm(5)), end: Pt(x: .mm(20), y: .mm(5)), width: .mm(0.3), layer: 0, net: nil),
		]
		let partial = Rect(from: Pt(x: 0, y: 0), to: Pt(x: .mm(12), y: .mm(10)))
		XCTAssertEqual(board.refs(in: partial, layer: 0, whole: true), [])
		XCTAssertEqual(board.refs(in: partial, layer: 0), [.trace(0)])

		let whole = Rect(from: Pt(x: 0, y: 0), to: Pt(x: .mm(25), y: .mm(10)))
		XCTAssertEqual(board.refs(in: whole, layer: 0, whole: true), [.trace(0), .trace(1)])
	}

	func testARouteIsConnectedWhereItLandsOnCopperAndNowhereElse() {
		var board = board()
		board.footprints = [
			Footprint(spec: .init(kind: .chip, chip: .c0805), reference: "R1", at: Pt(x: .mm(30), y: .mm(10))),
		]
		board.vias = [Via(at: Pt(x: .mm(20), y: .mm(20)), drill: .mm(0.3), pad: .mm(0.6), from: 0, to: 3, net: nil)]
		board.traces = [trace(from: Pt(x: .mm(5), y: .mm(5)), to: Pt(x: .mm(10), y: .mm(5)))]

		let pad = board.footprints[0].placedPads[0].at
		XCTAssertTrue(board.isConnection(pad, layer: 0))
		XCTAssertTrue(board.isConnection(Pt(x: .mm(20), y: .mm(20)), layer: 2))
		XCTAssertTrue(board.isConnection(Pt(x: .mm(10), y: .mm(5)), layer: 0))

		// Mid air, mid segment, and the same endpoint on another layer
		XCTAssertFalse(board.isConnection(Pt(x: .mm(40), y: .mm(30)), layer: 0))
		XCTAssertFalse(board.isConnection(Pt(x: .mm(7), y: .mm(5)), layer: 0))
		XCTAssertFalse(board.isConnection(Pt(x: .mm(10), y: .mm(5)), layer: 1))
	}

	func testSelectionModesCombineHitsWithTheInitialSelection() {
		let initial: Set<Ref> = [.trace(0), .via(1)]
		let hit: Set<Ref> = [.via(1), .hole(2)]

		XCTAssertEqual(SelectionMode.replace.apply(initial, hit), hit)
		XCTAssertEqual(SelectionMode.union.apply(initial, hit), [.trace(0), .via(1), .hole(2)])
		XCTAssertEqual(SelectionMode.subtract.apply(initial, hit), [.trace(0)])
		XCTAssertEqual(SelectionMode(shift: true, option: true), .subtract)
		XCTAssertEqual(SelectionMode(shift: false, option: false), .replace)
	}

	func testFootprintRotationAndFlipPlacePadsAbsolutely() {
		let at = Pt(x: .mm(10), y: .mm(20))
		var footprint = Footprint(spec: .init(kind: .chip, chip: .c0603), reference: "R1", at: at)

		XCTAssertEqual(footprint.placedPads.map(\.at), [
			Pt(x: .mm(9.2), y: .mm(20)),
			Pt(x: .mm(10.8), y: .mm(20)),
		])

		footprint.rotation = .r90
		XCTAssertEqual(footprint.placedPads.map(\.at), [
			Pt(x: .mm(10), y: .mm(19.2)),
			Pt(x: .mm(10), y: .mm(20.8)),
		])
		XCTAssertEqual(footprint.placedPads[0].size, Size(width: .mm(0.95), height: .mm(0.9)))

		footprint.rotation = .r0
		footprint.flipped = true
		XCTAssertEqual(footprint.placedPads.map(\.at), [
			Pt(x: .mm(10.8), y: .mm(20)),
			Pt(x: .mm(9.2), y: .mm(20)),
		])
		XCTAssertEqual(footprint.layer(of: footprint.placedPads[0], in: .four), Stack.four.bottom)
	}

	func testThroughHolePadsStayOnBothSidesWhenFlipped() {
		var footprint = Footprint(spec: .init(kind: .header, pins: 4, rows: 2), reference: "J1", at: .zero)
		XCTAssertEqual(footprint.pads.count, 8)
		XCTAssertTrue(footprint.pads.allSatisfy(\.isThrough))

		footprint.flipped = true
		XCTAssertTrue(footprint.placedPads.allSatisfy { $0.layer == 0 })
	}

	func testFootprintGeneratorsNumberPadsContiguously() {
		for spec in [
			Footprint.Spec(kind: .soic, pins: 8),
			Footprint.Spec(kind: .dip, pins: 14),
			Footprint.Spec(kind: .sot23),
			Footprint.Spec(kind: .chip),
		] {
			let footprint = Footprint(spec: spec, reference: "U1", at: .zero)
			let names = footprint.pads.map { Int($0.name) ?? 0 }.sorted()
			XCTAssertEqual(names, Array(1 ... footprint.pads.count), "\(spec.kind)")
		}
	}

	func testOvalPadsCapsuleAlongTheirLongAxisInEitherOrientation() {
		let at = Pt(x: .mm(5), y: .mm(5))
		let wide = Pad(at: at, size: Size(width: .mm(2), height: .mm(1)), shape: .oval, drill: 0, layer: 0, name: "1", net: nil)
		let tall = Pad(at: at, size: Size(width: .mm(1), height: .mm(2)), shape: .oval, drill: 0, layer: 0, name: "1", net: nil)
		let round = Pad(at: at, size: Size(width: .mm(1), height: .mm(1)), shape: .oval, drill: 0, layer: 0, name: "1", net: nil)

		guard case let .segment(a, b, width) = wide.figure else { return XCTFail("Expected a capsule") }
		XCTAssertEqual(a, Pt(x: .mm(4.5), y: .mm(5)))
		XCTAssertEqual(b, Pt(x: .mm(5.5), y: .mm(5)))
		XCTAssertEqual(width, .mm(1))

		guard case let .segment(c, d, height) = tall.figure else { return XCTFail("Expected a capsule") }
		XCTAssertEqual(c, Pt(x: .mm(5), y: .mm(4.5)))
		XCTAssertEqual(d, Pt(x: .mm(5), y: .mm(5.5)))
		XCTAssertEqual(height, .mm(1))

		XCTAssertEqual(round.figure, .round(at, .mm(1)))
		XCTAssertEqual(wide.figure.bounds.size, tall.figure.bounds.size.swapped)
		XCTAssertTrue(tall.figure.contains(Pt(x: .mm(5), y: .mm(5.4))))
		XCTAssertFalse(tall.figure.contains(Pt(x: .mm(5.6), y: .mm(5))))
	}

	func testClearancesSkipSameNetCopperAndAlwaysIncludeHoles() {
		var board = board()
		board.traces = [
			Trace(start: .zero, end: Pt(x: .mm(10), y: 0), width: .mm(0.25), layer: 1, net: 0),
			Trace(start: .zero, end: Pt(x: .mm(10), y: .mm(2)), width: .mm(0.25), layer: 1, net: 1),
			Trace(start: .zero, end: Pt(x: .mm(10), y: .mm(4)), width: .mm(0.25), layer: 1, net: nil),
		]
		board.vias = [Via(at: Pt(x: .mm(5), y: .mm(5)), drill: .mm(0.3), pad: .mm(0.6), from: 0, to: 3, net: 0)]
		board.holes = [Hole(at: Pt(x: .mm(20), y: .mm(20)), diameter: .mm(3.2))]

		XCTAssertEqual(board.clearances(on: 1, net: 0).count, 3)
		XCTAssertEqual(board.clearances(on: 1, net: nil).count, 4)

		let clearance = Int(board.rules.clearance)
		guard case let .round(_, diameter) = board.clearances(on: 1, net: 0).last else {
			return XCTFail("Hole clearance missing")
		}
		XCTAssertEqual(Int(diameter), .mm(3.2) + clearance * 2)
	}

	func testPlaneKnockoutsIgnoreLayersTheViaDoesNotSpan() {
		var board = board(.six)
		board.vias = [Via(at: Pt(x: .mm(5), y: .mm(5)), drill: .mm(0.3), pad: .mm(0.6), from: 0, to: 1, net: 1)]

		XCTAssertEqual(board.clearances(on: 1, net: 0).count, 1)
		XCTAssertEqual(board.clearances(on: 2, net: 0).count, 0)
	}

	func testRestackDropsUnreachableTracesAndCollapsedViasAndKeepsPlanes() {
		var board = board(.six)
		board.planes[1] = 0
		board.planes[4] = 1
		board.traces = [
			Trace(start: .zero, end: Pt(x: .mm(1), y: 0), width: .mm(0.25), layer: 0, net: nil),
			Trace(start: .zero, end: Pt(x: .mm(1), y: 0), width: .mm(0.25), layer: 4, net: nil),
		]
		board.vias = [
			Via(at: .zero, drill: .mm(0.3), pad: .mm(0.6), from: 0, to: 5, net: nil),
			Via(at: Pt(x: .mm(1), y: 0), drill: .mm(0.3), pad: .mm(0.6), from: 4, to: 5, net: nil),
		]

		XCTAssertEqual(board.restackLoss(.two), 2)
		board.restack(.two)

		XCTAssertEqual(board.stack, .two)
		XCTAssertEqual(board.planes, [nil, nil])
		XCTAssertEqual(board.traces.map(\.layer), [0])
		XCTAssertEqual(board.vias.count, 1)
		XCTAssertEqual(board.vias[0].span, 0 ... 1)
	}

	func testSetPlaneOnlyAppliesToInternalLayers() {
		var board = board()
		board.setPlane(0, on: 0)
		board.setPlane(0, on: 3)
		board.setPlane(0, on: 1)

		XCTAssertEqual(board.planes, [nil, 0, nil, nil])
	}

	func testRemovingANetClearsEveryReferenceToIt() {
		var design = Design(board: board())
		let net = design.addNet(name: "SIG")
		design.board.setPlane(net, on: 1)
		design.board.traces = [Trace(start: .zero, end: Pt(x: .mm(1), y: 0), width: .mm(0.25), layer: 0, net: net)]
		design.board.vias = [Via(at: .zero, drill: .mm(0.3), pad: .mm(0.6), from: 0, to: 3, net: net)]
		design.board.footprints = [Footprint(spec: .init(kind: .chip), reference: "R1", at: .zero)]
		design.board.footprints[0].pads.modifyEach { pad in pad.net = net }

		design.removeNet(net)

		XCTAssertNil(design.net(net))
		XCTAssertEqual(design.board.planes, [nil, nil, nil, nil])
		XCTAssertNil(design.board.traces[0].net)
		XCTAssertNil(design.board.vias[0].net)
		XCTAssertTrue(design.board.footprints[0].pads.allSatisfy { $0.net == nil })
	}

	func testRemoveDeletesEveryReferencedObjectWithoutShiftingTheWrongIndices() {
		var board = board()
		board.traces = (0 ..< 4).map { index in
			Trace(
				start: Pt(x: .mm(Double(index)), y: 0),
				end: Pt(x: .mm(Double(index)), y: .mm(1)),
				width: .mm(0.25),
				layer: 0,
				net: nil
			)
		}
		board.remove([.trace(0), .trace(2)])

		XCTAssertEqual(board.traces.map(\.start.x), [.mm(1), .mm(3)])
	}

	func testRotatingASelectionSpinsAroundItsOwnCentre() {
		var board = board()
		board.footprints = [
			Footprint(spec: .init(kind: .chip), reference: "R1", at: Pt(x: .mm(10), y: .mm(10))),
			Footprint(spec: .init(kind: .chip), reference: "R2", at: Pt(x: .mm(20), y: .mm(10))),
		]
		board.rotate([.footprint(0), .footprint(1)], clockwise: true)

		XCTAssertEqual(board.footprints[0].rotation, .r90)
		XCTAssertEqual(board.footprints[0].at.y, board.footprints[1].at.y - .mm(10))
		XCTAssertEqual(board.footprints[0].at.x, board.footprints[1].at.x)
	}

	func testMovingAFootprintDragsTheTraceEndsLandingOnItsPads() {
		var board = board()
		board.footprints = [
			Footprint(spec: .init(kind: .chip, chip: .c0805), reference: "R1", at: Pt(x: .mm(10), y: .mm(10))),
		]
		let pad = board.footprints[0].placedPads[0].at
		let away = Pt(x: .mm(30), y: .mm(10))
		board.traces = [
			Trace(start: pad, end: away, width: .mm(0.3), layer: 0, net: nil),
			Trace(start: pad, end: away, width: .mm(0.3), layer: 3, net: nil),
			Trace(start: away, end: Pt(x: .mm(35), y: .mm(10)), width: .mm(0.3), layer: 0, net: nil),
		]
		let delta = Pt(x: .mm(2), y: .mm(-1))
		board.move([.footprint(0)], by: delta, grid: .mm(1))

		XCTAssertEqual(board.footprints[0].at, Pt(x: .mm(12), y: .mm(9)))
		XCTAssertEqual(board.traces[0].start, pad + delta)
		XCTAssertEqual(board.traces[1].start, pad)

		// The leg the stretch folded off runs straight on into the segment past
		// `away`, so the two arrive as the one segment they look like
		XCTAssertEqual(board.traces.count, 3)
		XCTAssertEqual(board.traces[2].start, board.traces[0].end)
		XCTAssertEqual(board.traces[2].end, Pt(x: .mm(35), y: .mm(10)))
	}

	func testDraggingASegmentAlongItsOwnLineLeavesOneSegmentNotTwo() {
		var board = board()
		board.traces = [
			trace(from: Pt(x: 0, y: 0), to: Pt(x: .mm(5), y: .mm(5))),
			trace(from: Pt(x: .mm(5), y: .mm(5)), to: Pt(x: .mm(10), y: .mm(10))),
		]
		let moved = board.move([.trace(0)], by: Pt(x: .mm(1), y: .mm(1)), grid: .mm(1))

		XCTAssertEqual(board.traces.count, 1)
		XCTAssertEqual(board.traces[0].start, Pt(x: .mm(1), y: .mm(1)))
		XCTAssertEqual(board.traces[0].end, Pt(x: .mm(10), y: .mm(10)))

		// The selection follows the copper it was holding into the fused segment
		XCTAssertEqual(moved, [.trace(0)])
	}

	func testASegmentDraggedOntoItsNeighboursFarEndLeavesNoStub() {
		var board = board()
		board.traces = [
			trace(from: Pt(x: 0, y: 0), to: Pt(x: .mm(10), y: 0)),
			trace(from: Pt(x: .mm(10), y: 0), to: Pt(x: .mm(10), y: .mm(10))),
		]
		let moved = board.move([.trace(0)], by: Pt(x: 0, y: .mm(10)), grid: .mm(1))

		XCTAssertEqual(board.traces.count, 1)
		XCTAssertEqual(board.traces[0].start, Pt(x: 0, y: .mm(10)))
		XCTAssertEqual(board.traces[0].end, Pt(x: .mm(10), y: .mm(10)))
		XCTAssertEqual(moved, [.trace(0)])
	}

	func testCollinearCopperMeetingOnAPadStaysTwoSegments() {
		var board = board()
		board.footprints = [
			Footprint(spec: .init(kind: .header, pins: 2), reference: "J1", at: Pt(x: .mm(10), y: .mm(10))),
		]
		let pad = board.footprints[0].placedPads[0].at
		board.traces = [
			trace(from: Pt(x: pad.x - .mm(10), y: pad.y), to: pad),
			trace(from: pad, to: Pt(x: pad.x + .mm(10), y: pad.y)),
		]
		let delta = Pt(x: .mm(1), y: 0)
		board.move([.footprint(0)], by: delta, grid: .mm(1))

		XCTAssertEqual(board.traces.count, 2)
		XCTAssertEqual(board.traces[0].end, pad + delta)
		XCTAssertEqual(board.traces[1].start, pad + delta)
	}

	func testAStretchedSegmentFoldsIntoTwoLegsRatherThanLeaveTheGrid() {
		var board = board()
		board.footprints = [
			Footprint(spec: .init(kind: .header, pins: 2), reference: "J1", at: Pt(x: .mm(10), y: .mm(10))),
		]
		let pad = board.footprints[0].placedPads[0].at
		let via = Pt(x: pad.x + .mm(10), y: pad.y)
		board.vias = [Via(at: via, drill: .mm(0.3), pad: .mm(0.6), from: 0, to: 3, net: nil)]
		board.traces = [Trace(start: pad, end: via, width: .mm(0.3), layer: 0, net: nil)]

		let delta = Pt(x: 0, y: .mm(-1))
		board.move([.footprint(0)], by: delta, grid: .mm(1))

		XCTAssertEqual(board.traces.count, 2)
		XCTAssertEqual(board.traces[0].start, pad + delta)
		XCTAssertEqual(board.traces[0].end, Pt(x: pad.x + .mm(1), y: pad.y))
		XCTAssertEqual(board.traces[1].start, board.traces[0].end)
		XCTAssertEqual(board.traces[1].end, via)
		XCTAssertEqual(board.traces[1].width, board.traces[0].width)
		XCTAssertEqual(board.traces[1].layer, board.traces[0].layer)
		XCTAssertTrue(board.traces.allSatisfy { ($0.end - $0.start).isOctilinear })
	}

	func testAPlainCornerSlidesAlongInsteadOfCollectingAnotherSegment() {
		var board = board()
		board.footprints = [
			Footprint(spec: .init(kind: .header, pins: 2), reference: "J1", at: Pt(x: .mm(10), y: .mm(10))),
		]
		let pad = board.footprints[0].placedPads[0].at
		let corner = Pt(x: pad.x + .mm(10), y: pad.y)
		let far = Pt(x: corner.x + .mm(5), y: corner.y + .mm(5))
		board.traces = [
			Trace(start: pad, end: corner, width: .mm(0.3), layer: 0, net: nil),
			Trace(start: corner, end: far, width: .mm(0.3), layer: 0, net: nil),
		]

		let delta = Pt(x: 0, y: .mm(-1))
		board.move([.footprint(0)], by: delta, grid: .mm(1))

		let slid = Pt(x: pad.x + .mm(9), y: pad.y - .mm(1))
		XCTAssertEqual(board.traces.count, 2)
		XCTAssertEqual(board.traces[0].start, pad + delta)
		XCTAssertEqual(board.traces[0].end, slid)
		XCTAssertEqual(board.traces[1].start, slid)
		XCTAssertEqual(board.traces[1].end, far)
		XCTAssertTrue(board.traces.allSatisfy { ($0.end - $0.start).isOctilinear })
	}

	func testASegmentDrawnAtAFreeAngleKeepsIt() {
		var board = board()
		board.footprints = [
			Footprint(spec: .init(kind: .header, pins: 2), reference: "J1", at: Pt(x: .mm(10), y: .mm(10))),
		]
		let pad = board.footprints[0].placedPads[0].at
		let away = Pt(x: pad.x + .mm(20), y: pad.y + .mm(5))
		board.traces = [Trace(start: pad, end: away, width: .mm(0.3), layer: 0, net: nil)]

		let delta = Pt(x: 0, y: .mm(-1))
		board.move([.footprint(0)], by: delta, grid: .mm(1))

		XCTAssertEqual(board.traces.count, 1)
		XCTAssertEqual(board.traces[0].start, pad + delta)
		XCTAssertEqual(board.traces[0].end, away)
	}

	func testMovingOneSegmentSlidesTheCornersItsNeighboursRunInto() {
		var board = board()
		board.traces = [
			trace(from: Pt(x: 0, y: .mm(20)), to: Pt(x: .mm(5), y: .mm(15))),
			trace(from: Pt(x: .mm(5), y: .mm(15)), to: Pt(x: .mm(15), y: .mm(15))),
			trace(from: Pt(x: .mm(15), y: .mm(15)), to: Pt(x: .mm(20), y: .mm(20))),
			trace(from: Pt(x: .mm(20), y: .mm(20)), to: Pt(x: .mm(30), y: .mm(20))),
			trace(from: Pt(x: .mm(30), y: .mm(20)), to: Pt(x: .mm(35), y: .mm(15))),
		]
		let delta = Pt(x: 0, y: .mm(-1))
		board.move([.trace(2)], by: delta, grid: .mm(1))

		XCTAssertEqual(board.traces.count, 5)
		XCTAssertEqual(board.traces[2].start, Pt(x: .mm(15), y: .mm(14)))
		XCTAssertEqual(board.traces[2].end, Pt(x: .mm(20), y: .mm(19)))

		// The joints followed the segment and the corners beyond took up the slack
		XCTAssertEqual(board.traces[1].end, board.traces[2].start)
		XCTAssertEqual(board.traces[3].start, board.traces[2].end)
		XCTAssertEqual(board.traces[0].start, Pt(x: 0, y: .mm(20)))
		XCTAssertEqual(board.traces[0].end, Pt(x: .mm(6), y: .mm(14)))
		XCTAssertEqual(board.traces[1].start, board.traces[0].end)
		XCTAssertEqual(board.traces[3].end, Pt(x: .mm(31), y: .mm(19)))
		XCTAssertEqual(board.traces[4].start, board.traces[3].end)
		XCTAssertEqual(board.traces[4].end, Pt(x: .mm(35), y: .mm(15)))
		XCTAssertTrue(board.traces.allSatisfy { ($0.end - $0.start).isOctilinear })
	}

	func testASegmentDragLeavesCopperHeldByAViaWhereItIs() {
		var board = board()
		let via = Pt(x: 0, y: .mm(10))
		board.vias = [Via(at: via, drill: .mm(0.3), pad: .mm(0.6), from: 0, to: 3, net: nil)]
		board.traces = [
			trace(from: via, to: Pt(x: .mm(10), y: .mm(10))),
			trace(from: Pt(x: .mm(10), y: .mm(10)), to: Pt(x: .mm(15), y: .mm(15))),
		]
		board.move([.trace(1)], by: Pt(x: 0, y: .mm(-1)), grid: .mm(1))

		// The via holds its end, so the stretch folds rather than slides, and
		// it folds the way round that leaves the joint it hangs off: the
		// diagonal leg would meet the segment that moved at a right angle
		XCTAssertEqual(board.traces.count, 3)
		XCTAssertEqual(board.traces[0].start, Pt(x: .mm(1), y: .mm(9)))
		XCTAssertEqual(board.traces[0].end, Pt(x: .mm(10), y: .mm(9)))
		XCTAssertEqual(board.traces[1].start, board.traces[0].end)
		XCTAssertEqual(board.traces[2].start, board.traces[0].start)
		XCTAssertEqual(board.traces[2].end, via)
		XCTAssertTrue(board.traces.allSatisfy { ($0.end - $0.start).isOctilinear })
		XCTAssertEqual(sharpestTurn(board), 1)
	}

	func testOnlyCopperLeavingAPlainEndTiesARouteDown() {
		var board = board()
		let end = Pt(x: .mm(10), y: 0)
		board.traces = [trace(from: .zero, to: end)]

		XCTAssertEqual(board.heading(leaving: end, layer: 0), Pt(x: -1, y: 0))
		XCTAssertEqual(board.heading(leaving: .zero, layer: 0), Pt(x: 1, y: 0))
		XCTAssertNil(board.heading(leaving: end, layer: 1))
		XCTAssertNil(board.heading(leaving: Pt(x: .mm(5), y: 0), layer: 0))

		// A branch has no one heading to keep to, and a via joins copper
		// rather than bending it, so neither says which way a route may leave
		board.traces.append(trace(from: end, to: Pt(x: .mm(15), y: .mm(5))))
		XCTAssertNil(board.heading(leaving: end, layer: 0))

		board.traces.removeLast()
		board.vias = [Via(at: end, drill: .mm(0.3), pad: .mm(0.6), from: 0, to: 3, net: nil)]
		XCTAssertNil(board.heading(leaving: end, layer: 0))
	}

	func testAChainedRouteCarriesOnFromTheSegmentItJustDrew() throws {
		var board = board()
		board.traces = [trace(from: .zero, to: Pt(x: .mm(10), y: 0))]

		let start = Pt(x: .mm(10), y: 0)
		let leaving = try XCTUnwrap(board.heading(leaving: start, layer: 0))
		XCTAssertEqual(leaving, Pt(x: -1, y: 0))

		// The pointer is all but square to the copper drawn so far, so the next
		// segment takes the 45 nearest it instead
		let end = snapped45(from: start, to: Pt(x: .mm(11), y: .mm(10)), after: -leaving)
		XCTAssertEqual(end, Pt(x: .mm(15.5), y: .mm(5.5)))
		XCTAssertTrue((start - .zero).bends(to: end - start))
	}

	func testCopperThatAlreadyTurnedHardIsNotHeldHostage() {
		var board = board()
		// A corner sharper than a drag is allowed to leave, the way an older
		// document may well carry one
		board.traces = [
			trace(from: Pt(x: 0, y: .mm(20)), to: Pt(x: .mm(10), y: .mm(20))),
			trace(from: Pt(x: .mm(10), y: .mm(20)), to: Pt(x: .mm(5), y: .mm(25))),
		]
		let delta = Pt(x: .mm(1), y: .mm(1))
		board.move([.trace(0), .trace(1)], by: delta, grid: .mm(1))

		// Carried along as it was drawn rather than refused for a corner the
		// drag did not make
		XCTAssertEqual(board.traces.count, 2)
		XCTAssertEqual(board.traces[0].start, Pt(x: .mm(1), y: .mm(21)))
		XCTAssertEqual(board.traces[1].end, Pt(x: .mm(6), y: .mm(26)))
		XCTAssertEqual(sharpestTurn(board), 3)
	}

	func testATraceMovedWithItsFootprintDoesNotShiftTwice() {
		var board = board()
		board.footprints = [
			Footprint(spec: .init(kind: .header, pins: 2), reference: "J1", at: Pt(x: .mm(10), y: .mm(10))),
		]
		let pad = board.footprints[0].placedPads[0].at
		let away = Pt(x: .mm(20), y: .mm(10))
		board.traces = [Trace(start: pad, end: away, width: .mm(0.3), layer: 2, net: nil)]

		let delta = Pt(x: .mm(1), y: 0)
		board.move([.footprint(0), .trace(0)], by: delta, grid: .mm(1))

		XCTAssertEqual(board.traces[0].start, pad + delta)
		XCTAssertEqual(board.traces[0].end, away + delta)
	}

	func testDuplicateOffsetsCopiesAndRenamesFootprints() {
		var board = board()
		board.footprints = [Footprint(spec: .init(kind: .chip), reference: "R1", at: Pt(x: .mm(10), y: .mm(10)))]
		let created = board.duplicate([.footprint(0)], by: Pt(x: .mm(1), y: .mm(1)))

		XCTAssertEqual(created, [.footprint(1)])
		XCTAssertEqual(board.footprints[1].reference, "R2")
		XCTAssertEqual(board.footprints[1].at, Pt(x: .mm(11), y: .mm(11)))
	}

	func testTraceSessionCommitsOnDragAndChainsFromTheLastEndpoint() {
		var state = LayoutState()
		state.tool = .trace
		state.traceWidth = .mm(0.3)
		state.layer = 1
		state.net = 7

		state.beginTrace(at: .zero)
		XCTAssertNil(state.endTrace())
		XCTAssertEqual(state.traceSession?.phase, .pending)

		state.beginTrace(at: Pt(x: .mm(5), y: 0))
		state.updateTrace(to: Pt(x: .mm(5), y: 0))

		let trace = state.endTrace()
		XCTAssertEqual(trace?.start, .zero)
		XCTAssertEqual(trace?.end, Pt(x: .mm(5), y: 0))
		XCTAssertEqual(trace?.width, .mm(0.3))
		XCTAssertEqual(trace?.layer, 1)
		XCTAssertEqual(trace?.net, 7)

		XCTAssertEqual(state.traceSession?.start, Pt(x: .mm(5), y: 0))
		XCTAssertEqual(state.traceSession?.phase, .pending)

		state.tool = .select
		XCTAssertNil(state.traceSession)
	}

	func testLayerCyclingWrapsAroundTheStack() {
		var state = LayoutState()
		state.nextLayer(.four)
		state.nextLayer(.four)
		XCTAssertEqual(state.layer, 2)
		state.prevLayer(.four)
		XCTAssertEqual(state.layer, 1)
		state.layer = 0
		state.prevLayer(.four)
		XCTAssertEqual(state.layer, 3)

		state.clampLayer(.two)
		XCTAssertEqual(state.layer, 1)
	}

	@MainActor
	func testCanvasRendersAPopulatedBoardWithoutFailing() throws {
		var board = board(.six)
		board.planes[2] = 0
		board.traces = [
			Trace(start: Pt(x: .mm(2), y: .mm(2)), end: Pt(x: .mm(20), y: .mm(20)), width: .mm(0.25), layer: 0, net: 0),
			Trace(start: Pt(x: .mm(2), y: .mm(30)), end: Pt(x: .mm(30), y: .mm(30)), width: .mm(0.4), layer: 2, net: 1),
		]
		board.vias = [
			Via(at: Pt(x: .mm(20), y: .mm(20)), drill: .mm(0.3), pad: .mm(0.6), from: 0, to: 5, net: 0),
			Via(at: Pt(x: .mm(24), y: .mm(20)), drill: .mm(0.3), pad: .mm(0.6), from: 0, to: 5, net: 1),
		]
		board.holes = [Hole(at: Pt(x: .mm(45), y: .mm(35)), diameter: .mm(3.2))]
		board.footprints = [
			Footprint(spec: .init(kind: .soic, pins: 14), reference: "U1", at: Pt(x: .mm(15), y: .mm(15))),
			Footprint(spec: .init(kind: .header, pins: 5, rows: 2), reference: "J1", at: Pt(x: .mm(38), y: .mm(12))),
			Footprint(spec: .init(kind: .chip, chip: .c0805), reference: "R1", at: Pt(x: .mm(8), y: .mm(32))),
		]

		let view = LayoutView(design: .constant(Design(board: board)), state: .constant(LayoutState()))
		let renderer = ImageRenderer(
			content: SwiftUI.Canvas { ctx, size in view.render(in: ctx, size: size) }
				.frame(width: 480.0, height: 400.0)
		)
		XCTAssertNotNil(renderer.nsImage)
	}

	func testADragThatWouldSquareACornerBreaksItIntoTwo45s() {
		var board = board()
		board.traces = [
			trace(from: Pt(x: 0, y: .mm(20)), to: Pt(x: .mm(10), y: .mm(20))),
			trace(from: Pt(x: .mm(10), y: .mm(20)), to: Pt(x: .mm(20), y: .mm(30))),
		]
		board.move([.trace(1)], by: Pt(x: 0, y: .mm(-10)), grid: .mm(1))

		// The stretched segment lands back on the grid on its own, but it meets
		// the copper that moved square, so the corner comes apart: both legs
		// give up a grid step and a short segment joins where they left off
		XCTAssertEqual(board.traces.count, 3)
		XCTAssertEqual(board.traces[0].start, Pt(x: 0, y: .mm(20)))
		XCTAssertEqual(board.traces[0].end, Pt(x: .mm(9), y: .mm(11)))
		XCTAssertEqual(board.traces[2].start, Pt(x: .mm(9), y: .mm(11)))
		XCTAssertEqual(board.traces[2].end, Pt(x: .mm(11), y: .mm(11)))
		XCTAssertEqual(board.traces[1].start, Pt(x: .mm(11), y: .mm(11)))
		XCTAssertEqual(board.traces[1].end, Pt(x: .mm(20), y: .mm(20)))

		XCTAssertEqual(board.traces[2].width, board.traces[0].width)
		XCTAssertEqual(board.traces[2].layer, board.traces[0].layer)
		XCTAssertTrue(board.traces.allSatisfy { ($0.end - $0.start).isOctilinear })
		XCTAssertEqual(sharpestTurn(board), 1)
	}

	func testAViaCarriedOffAJunctionLeavesACornerThatComesApart() {
		var board = board()
		let junction = Pt(x: .mm(10), y: .mm(20))
		board.traces = [
			trace(from: Pt(x: 0, y: .mm(20)), to: junction),
			trace(from: junction, to: Pt(x: .mm(10), y: .mm(30))),
		]
		board.vias = [Via(at: junction, drill: .mm(0.3), pad: .mm(0.6), from: 0, to: 3, net: nil)]

		// Square copper is fine while a via joins it rather than bending it
		XCTAssertEqual(sharpestTurn(board), 0)

		board.move([.via(0)], by: Pt(x: .mm(5), y: .mm(5)), grid: .mm(1))

		// The via gone, the copper it held is a plain corner turning square, so
		// it comes apart into the two 45s it is really made of
		XCTAssertEqual(board.traces.count, 3)
		XCTAssertEqual(board.traces[0].end, Pt(x: .mm(9), y: .mm(20)))
		XCTAssertEqual(board.traces[1].start, Pt(x: .mm(10), y: .mm(21)))
		XCTAssertEqual(board.traces[2].start, Pt(x: .mm(9), y: .mm(20)))
		XCTAssertEqual(board.traces[2].end, Pt(x: .mm(10), y: .mm(21)))
		XCTAssertTrue(board.traces.allSatisfy { ($0.end - $0.start).isOctilinear })
		XCTAssertEqual(sharpestTurn(board), 1)
	}

	func testADragThatDoublesCopperBackOnItselfIsRefusedWhole() {
		var board = board()
		board.traces = [
			trace(from: Pt(x: 0, y: .mm(20)), to: Pt(x: .mm(10), y: .mm(20))),
			trace(from: Pt(x: .mm(10), y: .mm(20)), to: Pt(x: .mm(20), y: .mm(10))),
		]
		let stored = board

		// Nothing short of a loop turns that corner 45 degrees at a time, so
		// the copper does not follow the pointer at all
		let moved = board.move([.trace(1)], by: Pt(x: .mm(-10), y: .mm(10)), grid: .mm(1))
		XCTAssertNil(moved)
		XCTAssertEqual(board, stored)
	}

	func testADragIsRefusedWhereALegHasNoGridStepToGive() {
		var board = board()
		board.traces = [
			trace(from: Pt(x: 0, y: .mm(20)), to: Pt(x: .mm(10), y: .mm(20))),
			trace(from: Pt(x: .mm(10), y: .mm(20)), to: Pt(x: .mm(11), y: .mm(21))),
		]
		let stored = board

		// The same drag as the corner that comes apart, but the leg that would
		// have to give up a grid step is only one step long to begin with
		board.move([.trace(1)], by: Pt(x: 0, y: .mm(-10)), grid: .mm(1))
		XCTAssertEqual(board, stored)

		// On a finer grid the same corner has a step to spare
		board.move([.trace(1)], by: Pt(x: 0, y: .mm(-10)), grid: .mm(0.25))
		XCTAssertEqual(board.traces.count, 3)
		XCTAssertEqual(sharpestTurn(board), 1)
	}

	func testBoardRoundTripsThroughJSON() throws {
		var board = board(.six)
		board.planes[2] = 1
		board.traces = [Trace(start: .zero, end: Pt(x: .mm(5), y: .mm(5)), width: .mm(0.25), layer: 3, net: 1)]
		board.vias = [Via(at: Pt(x: .mm(2), y: .mm(2)), drill: .mm(0.3), pad: .mm(0.6), from: 0, to: 5, net: 1)]
		board.holes = [Hole(at: Pt(x: .mm(3), y: .mm(3)), diameter: .mm(3.2))]
		board.footprints = [Footprint(spec: .init(kind: .soic, pins: 8), reference: "U1", at: Pt(x: .mm(20), y: .mm(20)))]

		let data = try JSONEncoder().encode(board)
		XCTAssertEqual(try JSONDecoder().decode(Board.self, from: data), board)
	}
}
