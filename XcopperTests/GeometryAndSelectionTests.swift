import SwiftUI
import XCTest
@testable import Xcopper

final class GeometryAndSelectionTests: XCTestCase {

	private func board(_ stack: Stack = .four) -> Board {
		Board(size: Size(width: .mm(50), height: .mm(40)), stack: stack)
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

	func testGridSnapRoundsToNearestStepInBothDirections() {
		let grid = Nm.mm(0.25)
		XCTAssertEqual(Pt(x: .mm(0.3), y: .mm(-0.3)).snapped(to: grid), Pt(x: .mm(0.25), y: .mm(-0.25)))
		XCTAssertEqual(Pt(x: .mm(0.13), y: .mm(0.12)).snapped(to: grid), Pt(x: .mm(0.25), y: 0))
		XCTAssertEqual(Pt(x: 7, y: 7).snapped(to: 0), Pt(x: 7, y: 7))
	}

	func testGridPresetsUseExactImperialPitches() {
		XCTAssertEqual(Nm.grids, [.mil(5), .mil(10), .mil(25), .mil(50), .mil(100)])
		XCTAssertEqual(Nm.grids.map(\.label), ["0.127", "0.254", "0.635", "1.27", "2.54"])
		XCTAssertEqual(LayoutState().grid, .mil(10))
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
			Trace(start: Pt(x: .mm(1), y: .mm(1)), end: Pt(x: .mm(30), y: .mm(30)), width: .mm(0.25), layer: 0, net: nil),
			Trace(start: Pt(x: .mm(2), y: .mm(2)), end: Pt(x: .mm(4), y: .mm(4)), width: .mm(0.25), layer: 2, net: nil),
		]
		board.holes = [Hole(at: Pt(x: .mm(3), y: .mm(3)), diameter: .mm(3.2))]

		let rect = Rect(from: Pt(x: 0, y: 0), to: Pt(x: .mm(10), y: .mm(10)))
		XCTAssertEqual(board.refs(in: rect, layer: 0), [.trace(0), .hole(0)])
		XCTAssertEqual(board.refs(in: rect, layer: 2), [.trace(2), .hole(0)])
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
