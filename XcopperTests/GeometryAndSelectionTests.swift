import SwiftUI
import XCTest
@testable import Xcopper

final class GeometryAndSelectionTests: XCTestCase {

	private func board(_ stack: Stack = .digital) -> Board {
		Board(size: Size(width: 50 * .mm, height: 40 * .mm), stack: stack)
	}

	private func trace(from start: Point, to end: Point, layer: Int = 0) -> Trace {
		Trace(start: start, end: end, width: 300, layer: layer, net: nil)
	}

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

	func testNewDesignDefaultsToFourBySixInchesAndTheAnalogStackup() {
		let design = Design()
		XCTAssertEqual(design.board.size, Size(width: 4 * .inch, height: 6 * .inch))
		XCTAssertEqual(design.board.stack, .analog)
		XCTAssertEqual(design.nets.map(\.name), ["GND", "VCC", "VEE"])
		XCTAssertEqual(design.net(2)?.name, "VEE")
	}

	func testEveryStackupSignalsOnItsOuterLayersAndPlanesOnTheRest() {
		XCTAssertEqual(Stack.classic.roles, ["SIG", "SIG"])
		XCTAssertEqual(Stack.digital.roles, ["SIG", "GND", "VCC", "SIG"])
		XCTAssertEqual(Stack.analog.roles, ["SIG", "GND", "VCC", "VEE", "GND", "SIG"])

		for stack in Stack.allCases {
			XCTAssertEqual(stack.signals, [stack.top, stack.bottom])
			XCTAssertNil(stack.plane(of: stack.top))
			XCTAssertNil(stack.plane(of: stack.bottom))
			for layer in stack.internals { XCTAssertNotNil(stack.plane(of: layer)) }
		}
	}

	func testPlanesAreTheStackupsNetsAndCannotBeRemoved() {
		var design = Design(board: board(.analog))
		XCTAssertEqual(design.planes, [nil, 0, 1, 2, 0, nil])

		design.removeNet(0)
		XCTAssertEqual(design.net(0)?.name, "GND")

		design.restack(.classic)
		XCTAssertEqual(design.planes, [nil, nil])

		design.removeNet(0)
		XCTAssertNil(design.net(0))
	}

	func testRestackingAStripedBoardBringsItsPlaneNets() {
		var design = Design(board: board(.classic))
		design.nets = []
		design.restack(.digital)

		XCTAssertEqual(design.nets.map(\.name), ["GND", "VCC"])
		XCTAssertEqual(design.planes, [nil, 0, 1, nil])
	}

	func testSnap45PicksNearestOctantAndProjectsOntoIt() {
		let origin = Point.zero

		XCTAssertEqual(
			snapped45(from: origin, to: Point(x: 10 * .mm, y: 1 * .mm)),
			Point(x: 10 * .mm, y: 0)
		)
		XCTAssertEqual(
			snapped45(from: origin, to: Point(x: 1 * .mm, y: 10 * .mm)),
			Point(x: 0, y: 10 * .mm)
		)
		let diagonal = snapped45(from: origin, to: Point(x: 10 * .mm, y: -8 * .mm))
		XCTAssertEqual(diagonal.x, -diagonal.y)
		XCTAssertEqual(diagonal.x, 9 * .mm)
		XCTAssertEqual(snapped45(from: origin, to: origin), origin)
	}

	func testCopperTurns45DegreesAtATimeOrCarriesStraightOn() {
		let east = Point(x: 1, y: 0)

		XCTAssertEqual(east.turn(to: Point(x: 10 * .mm, y: 0)), 0)
		XCTAssertEqual(east.turn(to: Point(x: 10 * .mm, y: 10 * .mm)), 1)
		XCTAssertEqual(east.turn(to: Point(x: 0, y: 10 * .mm)), 2)
		XCTAssertEqual(east.turn(to: Point(x: -10 * .mm, y: 10 * .mm)), 3)
		XCTAssertEqual(east.turn(to: Point(x: -10 * .mm, y: 0)), 4)

		XCTAssertTrue(east.bends(to: Point(x: 5 * .mm, y: -5 * .mm)))
		XCTAssertFalse(east.bends(to: Point(x: 0, y: 5 * .mm)))
		XCTAssertFalse(east.bends(to: Point(x: -5 * .mm, y: 5 * .mm)))

		XCTAssertNil(east.turn(to: Point(x: 10 * .mm, y: 3 * .mm)))
		XCTAssertTrue(east.bends(to: Point(x: 10 * .mm, y: 3 * .mm)))
	}

	func testARouteChainingOnCopperWillNotSquareTheCorner() {
		let start = Point.zero
		let east = Point(x: 1, y: 0)

		XCTAssertEqual(
			snapped45(from: start, to: Point(x: 10 * .mm, y: 0), after: east),
			Point(x: 10 * .mm, y: 0)
		)
		XCTAssertEqual(
			snapped45(from: start, to: Point(x: 10 * .mm, y: 9 * .mm), after: east),
			Point(x: 9_500, y: 9_500)
		)

		XCTAssertEqual(
			snapped45(from: start, to: Point(x: 1 * .mm, y: 10 * .mm), after: east),
			Point(x: 5_500, y: 5_500)
		)
		XCTAssertEqual(
			snapped45(from: start, to: Point(x: 1 * .mm, y: -10 * .mm), after: east),
			Point(x: 5_500, y: -5_500)
		)

		XCTAssertEqual(snapped45(from: start, to: Point(x: -10 * .mm, y: 1 * .mm), after: east), start)
	}

	func testGridSnapRoundsToNearestStepInBothDirections() {
		let grid = 250
		XCTAssertEqual(Point(x: 300, y: -300).snapped(to: grid), Point(x: 250, y: -250))
		XCTAssertEqual(Point(x: 130, y: 120).snapped(to: grid), Point(x: 250, y: 0))
		XCTAssertEqual(Point(x: 7, y: 7).snapped(to: 0), Point(x: 7, y: 7))
	}

	func testInchConversionPreservesBoardDimensions() {
		XCTAssertEqual(1 * .inch, 25_400)
		XCTAssertEqual(Double.inch(50_800), 2.0, accuracy: 0.000_000_01)
	}

	func testSnapTargetPrefersTheNearestPadOnTheRoutedLayer() {
		var board = board()
		board.footprints = [Footprint(spec: .init(kind: .chip, chip: .c0805), reference: "R1", at: Point(x: 10 * .mm, y: 10 * .mm))]
		board.vias = [Via(at: Point(x: 20 * .mm, y: 20 * .mm), net: 1)]

		let pad = board.footprints[0].placedPads[0].at
		let near = Point(x: pad.x + 100, y: pad.y)
		XCTAssertEqual(board.snapTarget(near: near, layer: 0, radius: 400)?.0, pad)

		XCTAssertNil(board.snapTarget(near: Point(x: 40 * .mm, y: 30 * .mm), layer: 0, radius: 400))

		let viaTarget = board.snapTarget(near: Point(x: 20_100, y: 20 * .mm), layer: 2, radius: 400)
		XCTAssertEqual(viaTarget?.0, Point(x: 20 * .mm, y: 20 * .mm))
		XCTAssertEqual(viaTarget?.1, 1)
	}

	func testHitTestRespectsLayerToleranceAndPrefersSmallerObjectKinds() {
		var board = board()
		board.traces = [
			Trace(start: Point(x: 0, y: 5 * .mm), end: Point(x: 10 * .mm, y: 5 * .mm), width: 250, layer: 0, net: nil),
			Trace(start: Point(x: 0, y: 9 * .mm), end: Point(x: 10 * .mm, y: 9 * .mm), width: 250, layer: 1, net: nil),
		]
		let tolerance = 50

		XCTAssertEqual(board.hitTest(at: Point(x: 5 * .mm, y: 5 * .mm), layer: 0, tolerance: tolerance), .trace(0))
		XCTAssertNil(board.hitTest(at: Point(x: 5 * .mm, y: 5 * .mm), layer: 1, tolerance: tolerance))
		XCTAssertEqual(board.hitTest(at: Point(x: 5 * .mm, y: 9 * .mm), layer: 1, tolerance: tolerance), .trace(1))

		XCTAssertNotNil(board.hitTest(at: Point(x: 0, y: 5 * .mm + 160), layer: 0, tolerance: tolerance))
		XCTAssertNil(board.hitTest(at: Point(x: 0, y: 5 * .mm + 300), layer: 0, tolerance: tolerance))

		board.vias = [Via(at: Point(x: 5 * .mm, y: 5 * .mm), net: nil)]
		board.holes = [Hole(at: Point(x: 5 * .mm, y: 5 * .mm), diameter: 1 * .mm)]
		board.footprints = [Footprint(spec: .init(kind: .chip, chip: .c0805), reference: "R1", at: Point(x: 5 * .mm, y: 5 * .mm))]
		let overlap = Point(x: 5 * .mm, y: 5 * .mm)
		XCTAssertEqual(board.hitTest(at: overlap, layer: 0, tolerance: tolerance), .trace(0))
		XCTAssertEqual(board.refs(at: overlap, layer: 0, tolerance: tolerance, whole: true), [.trace(0)])
		XCTAssertEqual(board.hitTest(at: overlap, layer: 1, tolerance: tolerance), .via(0))

		board.vias = []
		XCTAssertEqual(board.hitTest(at: overlap, layer: 1, tolerance: tolerance), .hole(0))
		board.holes = []
		XCTAssertEqual(board.hitTest(at: overlap, layer: 1, tolerance: tolerance), .footprint(0))
	}

	func testPadsSelectAndHighlightIndividuallyAfterRotationAndFlipping() {
		var board = board()
		board.footprints = [Footprint(spec: .init(kind: .chip, chip: .c0805), reference: "R1", at: Point(x: 10 * .mm, y: 10 * .mm))]
		for rotation in Rotation.allCases {
			for flipped in [false, true] {
				board.footprints[0].rotation = rotation
				board.footprints[0].flipped = flipped
				let footprint = board.footprints[0]
				let layer = flipped ? board.stack.bottom : board.stack.top
				for (index, pad) in footprint.placedPads.enumerated() {
					let ref = Ref.pad(0, index)
					XCTAssertEqual(board.hitTest(at: pad.at, layer: layer, tolerance: 0), .footprint(0))
					XCTAssertEqual(board.hitTest(at: pad.at, layer: layer, tolerance: 0, selection: [.footprint(0)]), ref)
					XCTAssertNotEqual(board.hitTest(at: pad.at, layer: board.stack.bottom - layer, tolerance: 0, selection: [.footprint(0)]), ref)
					XCTAssertEqual(board.figures(on: layer, of: [ref]), [pad.figure])
					XCTAssertEqual(board.figures(on: board.stack.bottom - layer, of: [ref]), [])
					XCTAssertEqual(board.bounds(of: [ref]), pad.figure.bounds)
					let box = Rect(center: pad.at, size: Size(width: 100, height: 100))
					XCTAssertEqual(board.refs(in: box, layer: layer), [])
					XCTAssertEqual(board.refs(in: box, layer: layer, whole: true), [])
				}
				XCTAssertEqual(board.hitTest(at: footprint.at, layer: layer, tolerance: 0), .footprint(0))
				XCTAssertEqual(board.refs(in: footprint.placedExtent, layer: layer), [.footprint(0)])
				XCTAssertEqual(Set(board.figures(on: layer, of: [.footprint(0), .pad(0, 0)])), Set(footprint.placedPads.map(\.figure)))
			}
		}
	}

	func testPadsBeatOverlappingFootprintBodiesAndThroughPadsSelectOnEveryLayer() {
		var board = board()
		board.footprints = [Footprint(spec: .init(kind: .chip, chip: .c0805), reference: "R1", at: Point(x: 10 * .mm, y: 10 * .mm))]
		board.footprints[0].pads[0].drill = 300
		let pad = board.footprints[0].placedPads[0]
		board.footprints.append(Footprint(spec: .init(kind: .chip, chip: .c0805), reference: "R2", at: pad.at))
		for layer in board.stack.copper {
			XCTAssertEqual(board.hitTest(at: pad.at, layer: layer, tolerance: 0), .footprint(1))
			XCTAssertEqual(board.hitTest(at: pad.at, layer: layer, tolerance: 0, selection: [.footprint(0)]), .pad(0, 0))
			XCTAssertEqual(board.figures(on: layer, of: [.pad(0, 0)]), [pad.figure])
		}
		board.traces = [trace(from: pad.at, to: pad.at + Point(x: 10 * .mm, y: 0))]
		XCTAssertEqual(board.hitTest(at: pad.at, layer: 0, tolerance: 0, selection: [.footprint(0)]), .trace(0))
	}

	func testRubberBandSelectionIsLayerFilteredAndNeedsWhollyContainedTraces() {
		var board = board()
		board.traces = [
			Trace(start: Point(x: 1 * .mm, y: 1 * .mm), end: Point(x: 5 * .mm, y: 5 * .mm), width: 250, layer: 0, net: nil),
			Trace(start: Point(x: 6 * .mm, y: 6 * .mm), end: Point(x: 30 * .mm, y: 30 * .mm), width: 250, layer: 0, net: nil),
			Trace(start: Point(x: 2 * .mm, y: 2 * .mm), end: Point(x: 4 * .mm, y: 4 * .mm), width: 250, layer: 2, net: nil),
		]
		board.holes = [Hole(at: Point(x: 3 * .mm, y: 3 * .mm), diameter: 3_200)]

		let rect = Rect(from: Point(x: 0, y: 0), to: Point(x: 10 * .mm, y: 10 * .mm))
		XCTAssertEqual(board.refs(in: rect, layer: 0), [.trace(0), .hole(0)])
		XCTAssertEqual(board.refs(in: rect, layer: 2), [.trace(2), .hole(0)])
	}

	func testHoldingCommandSelectsTheWholeRunATraceIsPartOf() {
		var board = board()
		board.traces = [
			Trace(start: Point(x: 5 * .mm, y: 10 * .mm), end: Point(x: 10 * .mm, y: 10 * .mm), width: 300, layer: 0, net: nil),
			Trace(start: Point(x: 10 * .mm, y: 10 * .mm), end: Point(x: 15 * .mm, y: 15 * .mm), width: 300, layer: 0, net: nil),
			Trace(start: Point(x: 15 * .mm, y: 15 * .mm), end: Point(x: 15 * .mm, y: 20 * .mm), width: 300, layer: 0, net: nil),
			Trace(start: Point(x: 15 * .mm, y: 15 * .mm), end: Point(x: 25 * .mm, y: 15 * .mm), width: 300, layer: 1, net: nil),
		]
		XCTAssertEqual(
			board.refs(at: Point(x: 7 * .mm, y: 10 * .mm), layer: 0, tolerance: 0, whole: true),
			[.trace(0), .trace(1), .trace(2)]
		)
		XCTAssertEqual(
			board.refs(at: Point(x: 20 * .mm, y: 15 * .mm), layer: 1, tolerance: 0, whole: true),
			[.trace(3)]
		)
		XCTAssertEqual(
			board.refs(at: Point(x: 40 * .mm, y: 30 * .mm), layer: 0, tolerance: 0, whole: true),
			[]
		)
	}

	func testARunStopsWhereCopperBranchesOrMeetsAPad() {
		var board = board()
		board.footprints = [
			Footprint(spec: .init(kind: .chip, chip: .c0805), reference: "R1", at: Point(x: 30 * .mm, y: 10 * .mm)),
		]
		let pad = board.footprints[0].placedPads[0].at
		board.traces = [
			Trace(start: Point(x: 10 * .mm, y: 10 * .mm), end: Point(x: 20 * .mm, y: 10 * .mm), width: 300, layer: 0, net: nil),
			Trace(start: Point(x: 20 * .mm, y: 10 * .mm), end: pad, width: 300, layer: 0, net: nil),
			Trace(start: Point(x: 20 * .mm, y: 10 * .mm), end: Point(x: 20 * .mm, y: 5 * .mm), width: 300, layer: 0, net: nil),
			Trace(start: pad, end: Point(x: pad.x, y: 20 * .mm), width: 300, layer: 0, net: nil),
		]
		XCTAssertEqual(board.run(of: 0), [0])
		XCTAssertEqual(board.run(of: 1), [1])
		XCTAssertEqual(board.run(of: 3), [3])
	}

	func testSelectionTakesTheOneSegmentUnderThePointerOrInsideTheBand() {
		var board = board()
		board.traces = [
			trace(from: Point(x: 5 * .mm, y: 10 * .mm), to: Point(x: 10 * .mm, y: 10 * .mm)),
			trace(from: Point(x: 10 * .mm, y: 10 * .mm), to: Point(x: 15 * .mm, y: 15 * .mm)),
		]
		XCTAssertEqual(board.refs(at: Point(x: 7 * .mm, y: 10 * .mm), layer: 0, tolerance: 0), [.trace(0)])

		let partial = Rect(from: Point(x: 0, y: 0), to: Point(x: 12 * .mm, y: 12 * .mm))
		XCTAssertEqual(board.refs(in: partial, layer: 0), [.trace(0)])

		let clipped = Rect(from: Point(x: 0, y: 0), to: Point(x: 8 * .mm, y: 12 * .mm))
		XCTAssertEqual(board.refs(in: clipped, layer: 0), [])
	}

	func testARubberBandTakesARunOnlyWhenItCoversAllOfIt() {
		var board = board()
		board.traces = [
			Trace(start: Point(x: 5 * .mm, y: 5 * .mm), end: Point(x: 10 * .mm, y: 5 * .mm), width: 300, layer: 0, net: nil),
			Trace(start: Point(x: 10 * .mm, y: 5 * .mm), end: Point(x: 20 * .mm, y: 5 * .mm), width: 300, layer: 0, net: nil),
		]
		let partial = Rect(from: Point(x: 0, y: 0), to: Point(x: 12 * .mm, y: 10 * .mm))
		XCTAssertEqual(board.refs(in: partial, layer: 0, whole: true), [])
		XCTAssertEqual(board.refs(in: partial, layer: 0), [.trace(0)])

		let whole = Rect(from: Point(x: 0, y: 0), to: Point(x: 25 * .mm, y: 10 * .mm))
		XCTAssertEqual(board.refs(in: whole, layer: 0, whole: true), [.trace(0), .trace(1)])
	}

	func testARouteIsConnectedWhereItLandsOnCopperAndNowhereElse() {
		var board = board()
		board.footprints = [
			Footprint(spec: .init(kind: .chip, chip: .c0805), reference: "R1", at: Point(x: 30 * .mm, y: 10 * .mm)),
		]
		board.vias = [Via(at: Point(x: 20 * .mm, y: 20 * .mm), net: nil)]
		board.traces = [trace(from: Point(x: 5 * .mm, y: 5 * .mm), to: Point(x: 10 * .mm, y: 5 * .mm))]

		let pad = board.footprints[0].placedPads[0].at
		XCTAssertTrue(board.isConnection(pad, layer: 0))
		XCTAssertTrue(board.isConnection(Point(x: 20 * .mm, y: 20 * .mm), layer: 2))
		XCTAssertTrue(board.isConnection(Point(x: 10 * .mm, y: 5 * .mm), layer: 0))

		XCTAssertFalse(board.isConnection(Point(x: 40 * .mm, y: 30 * .mm), layer: 0))
		XCTAssertFalse(board.isConnection(Point(x: 7 * .mm, y: 5 * .mm), layer: 0))
		XCTAssertFalse(board.isConnection(Point(x: 10 * .mm, y: 5 * .mm), layer: 1))
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

	func testConnectivityResolvesLongChainsAndKeepsSeparateIslands() {
		var connections = UnionFind<Int>()
		for index in 0 ..< 50_000 { connections.union(index, index + 1) }
		XCTAssertEqual(connections.find(0), connections.find(50_000))
		XCTAssertEqual(connections.find(25_000), connections.find(0))
		connections.union(-1, -2)
		XCTAssertNotEqual(connections.find(-1), connections.find(0))
		connections.union(-2, 0)
		XCTAssertEqual(connections.find(-1), connections.find(50_000))
	}

	func testAWanderingClickNeitherBandsNorMovesAtAnyMagnification() {
		let press = CGPoint(x: 120.0, y: 90.0)
		let wobble = CGPoint(x: 122.0, y: 92.0)
		let grid = 2_540

		for scale in [4.0, 40.0, 400.0] as [CGFloat] {
			let start = Layout.point(press, scale: scale)
			let current = Layout.point(Layout.reached(from: press, to: wobble), scale: scale)
			XCTAssertEqual(current, start)

			let select = SelectSession<Ref>(start: start, end: current, mode: .replace, initial: [])
			let move = MoveSession(start: start.snapped(to: grid), end: current.snapped(to: grid))
			XCTAssertFalse(select.didDrag)
			XCTAssertFalse(move.didMove)
		}

		XCTAssertNotEqual(Layout.point(wobble, scale: 400.0), Layout.point(press, scale: 400.0))
		XCTAssertNotEqual(Layout.point(wobble, scale: 4.0), Layout.point(press, scale: 4.0))
	}

	func testOvalPadsCapsuleAlongTheirLongAxisInEitherOrientation() {
		let at = Point(x: 5 * .mm, y: 5 * .mm)
		let wide = Pad(at: at, size: Size(width: 2 * .mm, height: 1 * .mm), shape: .oval, drill: 0, layer: 0, name: "1", net: nil)
		let tall = Pad(at: at, size: Size(width: 1 * .mm, height: 2 * .mm), shape: .oval, drill: 0, layer: 0, name: "1", net: nil)
		let round = Pad(at: at, size: Size(width: 1 * .mm, height: 1 * .mm), shape: .oval, drill: 0, layer: 0, name: "1", net: nil)

		guard case let .segment(a, b, width) = wide.figure else { return XCTFail("Expected a capsule") }
		XCTAssertEqual(a, Point(x: 4_500, y: 5 * .mm))
		XCTAssertEqual(b, Point(x: 5_500, y: 5 * .mm))
		XCTAssertEqual(width, 1 * .mm)

		guard case let .segment(c, d, height) = tall.figure else { return XCTFail("Expected a capsule") }
		XCTAssertEqual(c, Point(x: 5 * .mm, y: 4_500))
		XCTAssertEqual(d, Point(x: 5 * .mm, y: 5_500))
		XCTAssertEqual(height, 1 * .mm)

		XCTAssertEqual(round.figure, .round(at, 1 * .mm))
		XCTAssertEqual(wide.figure.bounds.size, tall.figure.bounds.size.swapped)
		XCTAssertTrue(tall.figure.contains(Point(x: 5 * .mm, y: 5_400)))
		XCTAssertFalse(tall.figure.contains(Point(x: 5_600, y: 5 * .mm)))
	}

	func testClearancesSkipSameNetCopperAndAlwaysIncludeHoles() {
		var board = board()
		board.traces = [
			Trace(start: .zero, end: Point(x: 10 * .mm, y: 0), width: 250, layer: 1, net: 0),
			Trace(start: .zero, end: Point(x: 10 * .mm, y: 2 * .mm), width: 250, layer: 1, net: 1),
			Trace(start: .zero, end: Point(x: 10 * .mm, y: 4 * .mm), width: 250, layer: 1, net: nil),
		]
		board.vias = [Via(at: Point(x: 5 * .mm, y: 5 * .mm), net: 0)]
		board.holes = [Hole(at: Point(x: 20 * .mm, y: 20 * .mm), diameter: 3_200)]

		XCTAssertEqual(board.clearances(on: 1, net: 0).count, 3)
		XCTAssertEqual(board.clearances(on: 1, net: nil).count, 4)

		let clearance = Int(board.rules.clearance)
		guard case let .round(_, diameter) = board.clearances(on: 1, net: 0).last else {
			return XCTFail("Hole clearance missing")
		}
		XCTAssertEqual(Int(diameter), 3_200 + clearance * 2)
	}

	func testPlaneKnockoutsIncludeViasOnEveryCopperLayer() {
		var board = board(.analog)
		board.vias = [Via(at: Point(x: 5 * .mm, y: 5 * .mm), net: 1)]

		for layer in board.stack.copper {
			XCTAssertEqual(board.clearances(on: layer, net: 0).count, 1)
		}
		XCTAssertTrue(board.clearances(on: board.stack.count, net: 0).isEmpty)
	}

	func testRestackCarriesSignalCopperOntoTheNewOuterLayers() {
		var board = board(.classic)
		board.traces = [
			Trace(start: .zero, end: Point(x: 1 * .mm, y: 0), width: 250, layer: 0, net: nil),
			Trace(start: .zero, end: Point(x: 1 * .mm, y: 0), width: 250, layer: 1, net: nil),
		]
		board.vias = [Via(at: .zero, net: nil)]

		board.restack(.analog)

		XCTAssertEqual(board.stack, .analog)
		XCTAssertEqual(board.traces.map(\.layer), [0, 5])
		XCTAssertEqual(board.objects.filter { $0.ref == .via(0) }.map(\.layers), [0 ... 5])

		board.restack(.digital)

		XCTAssertEqual(board.traces.map(\.layer), [0, 3])
		XCTAssertEqual(board.objects.filter { $0.ref == .via(0) }.map(\.layers), [0 ... 3])
	}

	func testRestackDropsCopperBuriedUnderTheNewPlanes() {
		var board = board(.analog)
		board.traces = [
			Trace(start: .zero, end: Point(x: 1 * .mm, y: 0), width: 250, layer: 0, net: nil),
			Trace(start: .zero, end: Point(x: 1 * .mm, y: 0), width: 250, layer: 3, net: nil),
		]

		board.restack(.classic)

		XCTAssertEqual(board.traces.map(\.layer), [0])
	}

	func testRemovingANetClearsEveryReferenceToIt() {
		var design = Design(board: board())
		let net = design.addNet(name: "SIG")
		design.board.traces = [Trace(start: .zero, end: Point(x: 1 * .mm, y: 0), width: 250, layer: 0, net: net)]
		design.board.vias = [Via(at: .zero, net: net)]
		design.board.footprints = [Footprint(spec: .init(kind: .chip), reference: "R1", at: .zero)]
		design.board.footprints[0].pads.modifyEach { pad in pad.net = net }

		design.removeNet(net)

		XCTAssertNil(design.net(net))
		XCTAssertNil(design.board.traces[0].net)
		XCTAssertNil(design.board.vias[0].net)
		XCTAssertTrue(design.board.footprints[0].pads.allSatisfy { $0.net == nil })
	}

	func testRemoveDeletesEveryReferencedObjectWithoutShiftingTheWrongIndices() {
		var board = board()
		board.traces = (0 ..< 4).map { index in
			Trace(
				start: Point(x: index * .mm, y: 0),
				end: Point(x: index * .mm, y: 1 * .mm),
				width: 250,
				layer: 0,
				net: nil
			)
		}
		board.remove([.trace(0), .trace(2)])

		XCTAssertEqual(board.traces.map(\.start.x), [1 * .mm, 3 * .mm])
	}

	func testRotatingASelectionSpinsAroundItsOwnCentre() {
		var board = board()
		board.footprints = [
			Footprint(spec: .init(kind: .chip), reference: "R1", at: Point(x: 10 * .mm, y: 10 * .mm)),
			Footprint(spec: .init(kind: .chip), reference: "R2", at: Point(x: 20 * .mm, y: 10 * .mm)),
		]
		board.rotate([.footprint(0), .footprint(1)], clockwise: true)

		XCTAssertEqual(board.footprints[0].rotation, .r90)
		XCTAssertEqual(board.footprints[0].at.y, board.footprints[1].at.y - 10 * .mm)
		XCTAssertEqual(board.footprints[0].at.x, board.footprints[1].at.x)
	}

	func testMovingAFootprintDragsTheTraceEndsLandingOnItsPads() {
		var board = board()
		board.footprints = [
			Footprint(spec: .init(kind: .chip, chip: .c0805), reference: "R1", at: Point(x: 10 * .mm, y: 10 * .mm)),
		]
		let pad = board.footprints[0].placedPads[0].at
		let away = Point(x: 30 * .mm, y: 10 * .mm)
		board.traces = [
			Trace(start: pad, end: away, width: 300, layer: 0, net: nil),
			Trace(start: pad, end: away, width: 300, layer: 3, net: nil),
			Trace(start: away, end: Point(x: 35 * .mm, y: 10 * .mm), width: 300, layer: 0, net: nil),
		]
		let delta = Point(x: 2 * .mm, y: -1 * .mm)
		board.move([.footprint(0)], by: delta, grid: 1 * .mm)

		XCTAssertEqual(board.footprints[0].at, Point(x: 12 * .mm, y: 9 * .mm))
		XCTAssertEqual(board.traces[0].start, pad + delta)
		XCTAssertEqual(board.traces[1].start, pad)

		XCTAssertEqual(board.traces.count, 3)
		XCTAssertEqual(board.traces[2].start, board.traces[0].end)
		XCTAssertEqual(board.traces[2].end, Point(x: 35 * .mm, y: 10 * .mm))
	}

	func testDraggingASegmentAlongItsOwnLineLeavesOneSegmentNotTwo() {
		var board = board()
		board.traces = [
			trace(from: Point(x: 0, y: 0), to: Point(x: 5 * .mm, y: 5 * .mm)),
			trace(from: Point(x: 5 * .mm, y: 5 * .mm), to: Point(x: 10 * .mm, y: 10 * .mm)),
		]
		let moved = board.move([.trace(0)], by: Point(x: 1 * .mm, y: 1 * .mm), grid: 1 * .mm)

		XCTAssertEqual(board.traces.count, 1)
		XCTAssertEqual(board.traces[0].start, Point(x: 1 * .mm, y: 1 * .mm))
		XCTAssertEqual(board.traces[0].end, Point(x: 10 * .mm, y: 10 * .mm))

		XCTAssertEqual(moved, [.trace(0)])
	}

	func testASegmentDraggedOntoItsNeighboursFarEndLeavesNoStub() {
		var board = board()
		board.traces = [
			trace(from: Point(x: 0, y: 0), to: Point(x: 10 * .mm, y: 0)),
			trace(from: Point(x: 10 * .mm, y: 0), to: Point(x: 10 * .mm, y: 10 * .mm)),
		]
		let moved = board.move([.trace(0)], by: Point(x: 0, y: 10 * .mm), grid: 1 * .mm)

		XCTAssertEqual(board.traces.count, 1)
		XCTAssertEqual(board.traces[0].start, Point(x: 0, y: 10 * .mm))
		XCTAssertEqual(board.traces[0].end, Point(x: 10 * .mm, y: 10 * .mm))
		XCTAssertEqual(moved, [.trace(0)])
	}

	func testCollinearCopperMeetingOnAPadStaysTwoSegments() {
		var board = board()
		board.footprints = [
			Footprint(spec: .init(kind: .header, pins: 2), reference: "J1", at: Point(x: 10 * .mm, y: 10 * .mm)),
		]
		let pad = board.footprints[0].placedPads[0].at
		board.traces = [
			trace(from: Point(x: pad.x - 10 * .mm, y: pad.y), to: pad),
			trace(from: pad, to: Point(x: pad.x + 10 * .mm, y: pad.y)),
		]
		let delta = Point(x: 1 * .mm, y: 0)
		board.move([.footprint(0)], by: delta, grid: 1 * .mm)

		XCTAssertEqual(board.traces.count, 2)
		XCTAssertEqual(board.traces[0].end, pad + delta)
		XCTAssertEqual(board.traces[1].start, pad + delta)
	}

	func testAStretchedSegmentFoldsIntoTwoLegsRatherThanLeaveTheGrid() {
		var board = board()
		board.footprints = [
			Footprint(spec: .init(kind: .header, pins: 2), reference: "J1", at: Point(x: 10 * .mm, y: 10 * .mm)),
		]
		let pad = board.footprints[0].placedPads[0].at
		let via = Point(x: pad.x + 10 * .mm, y: pad.y)
		board.vias = [Via(at: via, net: nil)]
		board.traces = [Trace(start: pad, end: via, width: 300, layer: 0, net: nil)]

		let delta = Point(x: 0, y: -1 * .mm)
		board.move([.footprint(0)], by: delta, grid: 1 * .mm)

		XCTAssertEqual(board.traces.count, 2)
		XCTAssertEqual(board.traces[0].start, pad + delta)
		XCTAssertEqual(board.traces[0].end, Point(x: pad.x + 1 * .mm, y: pad.y))
		XCTAssertEqual(board.traces[1].start, board.traces[0].end)
		XCTAssertEqual(board.traces[1].end, via)
		XCTAssertEqual(board.traces[1].width, board.traces[0].width)
		XCTAssertEqual(board.traces[1].layer, board.traces[0].layer)
		XCTAssertTrue(board.traces.allSatisfy { ($0.end - $0.start).isOctilinear })
	}

	func testAPlainCornerSlidesAlongInsteadOfCollectingAnotherSegment() {
		var board = board()
		board.footprints = [
			Footprint(spec: .init(kind: .header, pins: 2), reference: "J1", at: Point(x: 10 * .mm, y: 10 * .mm)),
		]
		let pad = board.footprints[0].placedPads[0].at
		let corner = Point(x: pad.x + 10 * .mm, y: pad.y)
		let far = Point(x: corner.x + 5 * .mm, y: corner.y + 5 * .mm)
		board.traces = [
			Trace(start: pad, end: corner, width: 300, layer: 0, net: nil),
			Trace(start: corner, end: far, width: 300, layer: 0, net: nil),
		]

		let delta = Point(x: 0, y: -1 * .mm)
		board.move([.footprint(0)], by: delta, grid: 1 * .mm)

		let slid = Point(x: pad.x + 9 * .mm, y: pad.y - 1 * .mm)
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
			Footprint(spec: .init(kind: .header, pins: 2), reference: "J1", at: Point(x: 10 * .mm, y: 10 * .mm)),
		]
		let pad = board.footprints[0].placedPads[0].at
		let away = Point(x: pad.x + 20 * .mm, y: pad.y + 5 * .mm)
		board.traces = [Trace(start: pad, end: away, width: 300, layer: 0, net: nil)]

		let delta = Point(x: 0, y: -1 * .mm)
		board.move([.footprint(0)], by: delta, grid: 1 * .mm)

		XCTAssertEqual(board.traces.count, 1)
		XCTAssertEqual(board.traces[0].start, pad + delta)
		XCTAssertEqual(board.traces[0].end, away)
	}

	func testMovingOneSegmentStretchesTheNeighboursItHangsOff() {
		var board = board()
		board.traces = [
			trace(from: Point(x: 0, y: 20 * .mm), to: Point(x: 5 * .mm, y: 15 * .mm)),
			trace(from: Point(x: 5 * .mm, y: 15 * .mm), to: Point(x: 15 * .mm, y: 15 * .mm)),
			trace(from: Point(x: 15 * .mm, y: 15 * .mm), to: Point(x: 20 * .mm, y: 20 * .mm)),
			trace(from: Point(x: 20 * .mm, y: 20 * .mm), to: Point(x: 30 * .mm, y: 20 * .mm)),
			trace(from: Point(x: 30 * .mm, y: 20 * .mm), to: Point(x: 35 * .mm, y: 15 * .mm)),
		]
		let delta = Point(x: 0, y: -1 * .mm)
		board.move([.trace(2)], by: delta, grid: 1 * .mm)

		XCTAssertEqual(board.traces.count, 5)
		XCTAssertEqual(board.traces[2].start, Point(x: 16 * .mm, y: 15 * .mm))
		XCTAssertEqual(board.traces[2].end, Point(x: 21 * .mm, y: 20 * .mm))
		XCTAssertEqual(board.traces[1].end, board.traces[2].start)
		XCTAssertEqual(board.traces[3].start, board.traces[2].end)

		XCTAssertEqual(board.traces[1].start, Point(x: 5 * .mm, y: 15 * .mm))
		XCTAssertEqual(board.traces[3].end, Point(x: 30 * .mm, y: 20 * .mm))
		XCTAssertEqual(board.traces[0], trace(from: Point(x: 0, y: 20 * .mm), to: Point(x: 5 * .mm, y: 15 * .mm)))
		XCTAssertEqual(board.traces[4], trace(from: Point(x: 30 * .mm, y: 20 * .mm), to: Point(x: 35 * .mm, y: 15 * .mm)))
		XCTAssertTrue(board.traces.allSatisfy { ($0.end - $0.start).isOctilinear })
		XCTAssertEqual(sharpestTurn(board), 1)
	}

	func testTheBottomOfAUDraggedTowardsTheTopComesOutLonger() {
		var board = board()
		board.traces = [
			trace(from: Point(x: 0, y: 0), to: Point(x: 0, y: 10 * .mm)),
			trace(from: Point(x: 0, y: 10 * .mm), to: Point(x: 3 * .mm, y: 13 * .mm)),
			trace(from: Point(x: 3 * .mm, y: 13 * .mm), to: Point(x: 7 * .mm, y: 13 * .mm)),
			trace(from: Point(x: 7 * .mm, y: 13 * .mm), to: Point(x: 10 * .mm, y: 10 * .mm)),
			trace(from: Point(x: 10 * .mm, y: 10 * .mm), to: Point(x: 10 * .mm, y: 0)),
		]
		board.move([.trace(2)], by: Point(x: 0, y: -2 * .mm), grid: 1 * .mm)

		XCTAssertEqual(board.traces.count, 5)
		XCTAssertEqual(board.traces[2].start, Point(x: 1 * .mm, y: 11 * .mm))
		XCTAssertEqual(board.traces[2].end, Point(x: 9 * .mm, y: 11 * .mm))
		XCTAssertEqual(board.traces[1].start, Point(x: 0, y: 10 * .mm))
		XCTAssertEqual(board.traces[1].end, board.traces[2].start)
		XCTAssertEqual(board.traces[3].start, board.traces[2].end)
		XCTAssertEqual(board.traces[3].end, Point(x: 10 * .mm, y: 10 * .mm))
		XCTAssertEqual(board.traces[0].start, Point(x: 0, y: 0))
		XCTAssertEqual(board.traces[4].end, Point(x: 10 * .mm, y: 0))
		XCTAssertTrue(board.traces.allSatisfy { ($0.end - $0.start).isOctilinear })
		XCTAssertEqual(sharpestTurn(board), 1)
	}

	func testALegAStretchTakesUpToNothingGoesAwayWithTheDrag() {
		var board = board()
		board.traces = [
			trace(from: Point(x: 0, y: 0), to: Point(x: 0, y: 10 * .mm)),
			trace(from: Point(x: 0, y: 10 * .mm), to: Point(x: 3 * .mm, y: 13 * .mm)),
			trace(from: Point(x: 3 * .mm, y: 13 * .mm), to: Point(x: 7 * .mm, y: 13 * .mm)),
		]
		board.move([.trace(2)], by: Point(x: 0, y: -3 * .mm), grid: 1 * .mm)

		XCTAssertEqual(board.traces.count, 3)
		XCTAssertEqual(board.traces[0], trace(from: Point(x: 0, y: 0), to: Point(x: 0, y: 9 * .mm)))
		XCTAssertEqual(board.traces[1].start, Point(x: 1 * .mm, y: 10 * .mm))
		XCTAssertEqual(board.traces[1].end, Point(x: 7 * .mm, y: 10 * .mm))
		XCTAssertEqual(board.traces[2].start, Point(x: 0, y: 9 * .mm))
		XCTAssertEqual(board.traces[2].end, Point(x: 1 * .mm, y: 10 * .mm))
		XCTAssertEqual(sharpestTurn(board), 1)
	}

	func testASegmentDragLeavesCopperHeldByAViaWhereItIs() {
		var board = board()
		let via = Point(x: 0, y: 10 * .mm)
		board.vias = [Via(at: via, net: nil)]
		board.traces = [
			trace(from: via, to: Point(x: 10 * .mm, y: 10 * .mm)),
			trace(from: Point(x: 10 * .mm, y: 10 * .mm), to: Point(x: 15 * .mm, y: 15 * .mm)),
		]
		board.move([.trace(1)], by: Point(x: 0, y: -1 * .mm), grid: 1 * .mm)

		XCTAssertEqual(board.traces.count, 2)
		XCTAssertEqual(board.traces[0].start, via)
		XCTAssertEqual(board.traces[0].end, Point(x: 11 * .mm, y: 10 * .mm))
		XCTAssertEqual(board.traces[1].start, board.traces[0].end)
		XCTAssertEqual(board.traces[1].end, Point(x: 15 * .mm, y: 14 * .mm))
		XCTAssertTrue(board.traces.allSatisfy { ($0.end - $0.start).isOctilinear })
		XCTAssertEqual(sharpestTurn(board), 1)
	}

	func testOnlyCopperLeavingAPlainEndTiesARouteDown() {
		var board = board()
		let end = Point(x: 10 * .mm, y: 0)
		board.traces = [trace(from: .zero, to: end)]

		XCTAssertEqual(board.heading(leaving: end, layer: 0), Point(x: -1, y: 0))
		XCTAssertEqual(board.heading(leaving: .zero, layer: 0), Point(x: 1, y: 0))
		XCTAssertNil(board.heading(leaving: end, layer: 1))
		XCTAssertNil(board.heading(leaving: Point(x: 5 * .mm, y: 0), layer: 0))

		board.traces.append(trace(from: end, to: Point(x: 15 * .mm, y: 5 * .mm)))
		XCTAssertNil(board.heading(leaving: end, layer: 0))

		board.traces.removeLast()
		board.vias = [Via(at: end, net: nil)]
		XCTAssertNil(board.heading(leaving: end, layer: 0))
	}

	func testAChainedRouteCarriesOnFromTheSegmentItJustDrew() throws {
		var board = board()
		board.traces = [trace(from: .zero, to: Point(x: 10 * .mm, y: 0))]

		let start = Point(x: 10 * .mm, y: 0)
		let leaving = try XCTUnwrap(board.heading(leaving: start, layer: 0))
		XCTAssertEqual(leaving, Point(x: -1, y: 0))

		let end = snapped45(from: start, to: Point(x: 11 * .mm, y: 10 * .mm), after: -leaving)
		XCTAssertEqual(end, Point(x: 15_500, y: 5_500))
		XCTAssertTrue((start - .zero).bends(to: end - start))
	}

	func testCopperThatAlreadyTurnedHardIsNotHeldHostage() {
		var board = board()
		board.traces = [
			trace(from: Point(x: 0, y: 20 * .mm), to: Point(x: 10 * .mm, y: 20 * .mm)),
			trace(from: Point(x: 10 * .mm, y: 20 * .mm), to: Point(x: 5 * .mm, y: 25 * .mm)),
		]
		let delta = Point(x: 1 * .mm, y: 1 * .mm)
		board.move([.trace(0), .trace(1)], by: delta, grid: 1 * .mm)

		XCTAssertEqual(board.traces.count, 2)
		XCTAssertEqual(board.traces[0].start, Point(x: 1 * .mm, y: 21 * .mm))
		XCTAssertEqual(board.traces[1].end, Point(x: 6 * .mm, y: 26 * .mm))
		XCTAssertEqual(sharpestTurn(board), 3)
	}

	func testATraceMovedWithItsFootprintDoesNotShiftTwice() {
		var board = board()
		board.footprints = [
			Footprint(spec: .init(kind: .header, pins: 2), reference: "J1", at: Point(x: 10 * .mm, y: 10 * .mm)),
		]
		let pad = board.footprints[0].placedPads[0].at
		let away = Point(x: 20 * .mm, y: 10 * .mm)
		board.traces = [Trace(start: pad, end: away, width: 300, layer: 2, net: nil)]

		let delta = Point(x: 1 * .mm, y: 0)
		board.move([.footprint(0), .trace(0)], by: delta, grid: 1 * .mm)

		XCTAssertEqual(board.traces[0].start, pad + delta)
		XCTAssertEqual(board.traces[0].end, away + delta)
	}

	func testDuplicateOffsetsCopiesOfFootprints() {
		var board = board()
		board.footprints = [Footprint(spec: .init(kind: .chip), reference: "R1", at: Point(x: 10 * .mm, y: 10 * .mm))]
		let created = board.duplicate([.footprint(0)], by: Point(x: 1 * .mm, y: 1 * .mm))

		XCTAssertEqual(created, [.footprint(1)])
		XCTAssertEqual(board.footprints[1].at, Point(x: 11 * .mm, y: 11 * .mm))
	}

	func testTraceSessionCommitsOnDragAndChainsFromTheLastEndpoint() {
		var state = LayoutState()
		state.tool = .trace
		state.traceWidth = 300
		state.layer = 1
		state.net = 7

		state.beginTrace(at: .zero)
		XCTAssertNil(state.endTrace())
		XCTAssertEqual(state.traceSession?.phase, .pending)

		state.beginTrace(at: Point(x: 5 * .mm, y: 0))
		state.updateTrace(to: Point(x: 5 * .mm, y: 0))

		let trace = state.endTrace()
		XCTAssertEqual(trace?.start, .zero)
		XCTAssertEqual(trace?.end, Point(x: 5 * .mm, y: 0))
		XCTAssertEqual(trace?.width, 300)
		XCTAssertEqual(trace?.layer, 1)
		XCTAssertEqual(trace?.net, 7)

		XCTAssertEqual(state.traceSession?.start, Point(x: 5 * .mm, y: 0))
		XCTAssertEqual(state.traceSession?.phase, .pending)

		state.tool = .select
		XCTAssertNil(state.traceSession)
	}

	func testLayerCyclingVisitsTheSignalLayersOnly() {
		var state = LayoutState()
		state.nextLayer(.analog)
		XCTAssertEqual(state.layer, 5)
		state.nextLayer(.analog)
		XCTAssertEqual(state.layer, 0)
		state.prevLayer(.analog)
		XCTAssertEqual(state.layer, 5)

		state.clampLayer(.classic)
		XCTAssertEqual(state.layer, 1)

		state.layer = 2
		state.clampLayer(.digital)
		XCTAssertEqual(state.layer, 3)
	}

	@MainActor
	func testCanvasRendersAPopulatedBoardWithoutFailing() throws {
		var board = board(.analog)
		board.traces = [
			Trace(start: Point(x: 2 * .mm, y: 2 * .mm), end: Point(x: 20 * .mm, y: 20 * .mm), width: 250, layer: 0, net: 0),
			Trace(start: Point(x: 2 * .mm, y: 30 * .mm), end: Point(x: 30 * .mm, y: 30 * .mm), width: 400, layer: 5, net: 1),
		]
		board.vias = [
			Via(at: Point(x: 20 * .mm, y: 20 * .mm), net: 0),
			Via(at: Point(x: 24 * .mm, y: 20 * .mm), net: 1),
		]
		board.holes = [Hole(at: Point(x: 45 * .mm, y: 35 * .mm), diameter: 3_200)]
		board.footprints = [
			Footprint(spec: .init(kind: .soic, pins: 14), reference: "U1", at: Point(x: 15 * .mm, y: 15 * .mm)),
			Footprint(spec: .init(kind: .header, pins: 5, rows: 2), reference: "J1", at: Point(x: 38 * .mm, y: 12 * .mm)),
			Footprint(spec: .init(kind: .chip, chip: .c0805), reference: "R1", at: Point(x: 8 * .mm, y: 32 * .mm)),
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
			trace(from: Point(x: 0, y: 20 * .mm), to: Point(x: 10 * .mm, y: 20 * .mm)),
			trace(from: Point(x: 10 * .mm, y: 20 * .mm), to: Point(x: 20 * .mm, y: 30 * .mm)),
		]
		board.move([.trace(1)], by: Point(x: 0, y: -10 * .mm), grid: 1 * .mm)

		XCTAssertEqual(board.traces.count, 3)
		XCTAssertEqual(board.traces[0].start, Point(x: 0, y: 20 * .mm))
		XCTAssertEqual(board.traces[0].end, Point(x: 9 * .mm, y: 11 * .mm))
		XCTAssertEqual(board.traces[2].start, Point(x: 9 * .mm, y: 11 * .mm))
		XCTAssertEqual(board.traces[2].end, Point(x: 11 * .mm, y: 11 * .mm))
		XCTAssertEqual(board.traces[1].start, Point(x: 11 * .mm, y: 11 * .mm))
		XCTAssertEqual(board.traces[1].end, Point(x: 20 * .mm, y: 20 * .mm))

		XCTAssertEqual(board.traces[2].width, board.traces[0].width)
		XCTAssertEqual(board.traces[2].layer, board.traces[0].layer)
		XCTAssertTrue(board.traces.allSatisfy { ($0.end - $0.start).isOctilinear })
		XCTAssertEqual(sharpestTurn(board), 1)
	}

	func testAViaCarriedOffAJunctionLeavesACornerThatComesApart() {
		var board = board()
		let junction = Point(x: 10 * .mm, y: 20 * .mm)
		board.traces = [
			trace(from: Point(x: 0, y: 20 * .mm), to: junction),
			trace(from: junction, to: Point(x: 10 * .mm, y: 30 * .mm)),
		]
		board.vias = [Via(at: junction, net: nil)]

		XCTAssertEqual(sharpestTurn(board), 0)

		board.move([.via(0)], by: Point(x: 5 * .mm, y: 5 * .mm), grid: 1 * .mm)

		XCTAssertEqual(board.traces.count, 3)
		XCTAssertEqual(board.traces[0].end, Point(x: 9 * .mm, y: 20 * .mm))
		XCTAssertEqual(board.traces[1].start, Point(x: 10 * .mm, y: 21 * .mm))
		XCTAssertEqual(board.traces[2].start, Point(x: 9 * .mm, y: 20 * .mm))
		XCTAssertEqual(board.traces[2].end, Point(x: 10 * .mm, y: 21 * .mm))
		XCTAssertTrue(board.traces.allSatisfy { ($0.end - $0.start).isOctilinear })
		XCTAssertEqual(sharpestTurn(board), 1)
	}

	func testADragThatDoublesCopperBackOnItselfIsRefusedWhole() {
		var board = board()
		board.traces = [
			trace(from: Point(x: 0, y: 20 * .mm), to: Point(x: 10 * .mm, y: 20 * .mm)),
			trace(from: Point(x: 10 * .mm, y: 20 * .mm), to: Point(x: 20 * .mm, y: 10 * .mm)),
		]
		let stored = board

		let moved = board.move([.trace(1)], by: Point(x: -10 * .mm, y: 10 * .mm), grid: 1 * .mm)
		XCTAssertNil(moved)
		XCTAssertEqual(board, stored)
	}

	func testADragIsRefusedWhereALegHasNoGridStepToGive() {
		var board = board()
		board.traces = [
			trace(from: Point(x: 0, y: 20 * .mm), to: Point(x: 10 * .mm, y: 20 * .mm)),
			trace(from: Point(x: 10 * .mm, y: 20 * .mm), to: Point(x: 11 * .mm, y: 21 * .mm)),
		]
		let stored = board

		board.move([.trace(1)], by: Point(x: 0, y: -10 * .mm), grid: 1 * .mm)
		XCTAssertEqual(board, stored)

		board.move([.trace(1)], by: Point(x: 0, y: -10 * .mm), grid: 250)
		XCTAssertEqual(board.traces.count, 3)
		XCTAssertEqual(sharpestTurn(board), 1)
	}

	func testBoardRoundTripsThroughJSON() throws {
		var board = board(.analog)
		board.traces = [Trace(start: .zero, end: Point(x: 5 * .mm, y: 5 * .mm), width: 250, layer: 5, net: 1)]
		board.vias = [Via(at: Point(x: 2 * .mm, y: 2 * .mm), net: 1)]
		board.holes = [Hole(at: Point(x: 3 * .mm, y: 3 * .mm), diameter: 3_200)]
		board.footprints = [Footprint(spec: .init(kind: .soic, pins: 8), reference: "U1", at: Point(x: 20 * .mm, y: 20 * .mm))]

		let data = try JSONEncoder().encode(board)
		XCTAssertEqual(try JSONDecoder().decode(Board.self, from: data), board)
	}
}
