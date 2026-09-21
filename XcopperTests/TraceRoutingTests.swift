import XCTest
@testable import Xcopper

final class TraceRoutingTests: XCTestCase {
	private func point(_ x: µm, _ y: µm) -> Point { Point(x: x, y: y) }

	private func trace(_ start: Point, _ end: Point, layer: Int = 0) -> Trace {
		Trace(start: start, end: end, width: 400, layer: layer, net: 0)
	}

	private func routing(from start: Point, to end: Point) -> LayoutState {
		var state = LayoutState(stack: .classic)
		state.tool = .trace
		state.traceWidth = 400
		state.routingGrid = 500
		state.net = 0
		state.beginTrace(at: start)
		state.updateTrace(to: end)
		return state
	}

	private func assertStraight(_ board: Board, file: StaticString = #filePath, line: UInt = #line) {
		XCTAssertTrue(board.traces.allSatisfy { ($0.end - $0.start).isOctilinear }, file: file, line: line)
		for trace in board.traces {
			for point in [trace.start, trace.end] {
				XCTAssertLessThanOrEqual(board.turn(at: Junction(point: point, layer: trace.layer)) ?? 0, 1, file: file, line: line)
			}
		}
	}

	func testFinishingOnAPadStraightensTheWholeRunAndKeepsThePadConnection() {
		var design = Design(board: Board(stack: .classic))
		let footprint = Footprint(spec: .init(kind: .header, pins: 2), reference: "J1", at: point(30 * .mm, 20 * .mm))
		design.board.footprints = [footprint]
		let pad = footprint.placedPads[0].at
		let start = pad - point(20 * .mm, 5 * .mm)
		let corner = pad - point(10 * .mm, 3 * .mm)
		design.board.traces = [trace(start, corner)]
		var state = routing(from: corner, to: pad)

		XCTAssertTrue(state.endTrace(in: &design))

		assertStraight(design.board)
		XCTAssertEqual(design.board.run(of: 0), Set(design.board.traces.indices))
		XCTAssertEqual(design.board.traces.count { $0.start == start || $0.end == start }, 1)
		XCTAssertEqual(design.board.traces.count { $0.start == pad || $0.end == pad }, 1)
		XCTAssertEqual(design.board.footprints, [footprint])
		XCTAssertEqual(state.tool, .select)
		XCTAssertNil(state.traceSession)
	}

	func testFinishingOnATraceEndpointFusesCompatibleStraightSegments() {
		var design = Design(board: Board(stack: .classic))
		let start = point(10 * .mm, 10 * .mm)
		let joint = point(20 * .mm, 10 * .mm)
		let end = point(30 * .mm, 10 * .mm)
		design.board.traces = [trace(joint, end)]
		var state = routing(from: start, to: joint)
		state.selection = [.trace(0)]

		XCTAssertTrue(state.endTrace(in: &design))

		XCTAssertEqual(design.board.traces, [trace(start, end)])
		XCTAssertEqual(state.tool, .select)
		XCTAssertNil(state.traceSession)
		XCTAssertTrue(state.selection.isEmpty)
	}

	func testFinishingOnATraceEndpointStraightensTheJoin() {
		for rise in [0, 3 * µm.mm] {
			var design = Design(board: Board(stack: .classic))
			let start = point(10 * .mm, 10 * .mm - rise)
			let joint = point(20 * .mm, 10 * .mm)
			let end = point(20 * .mm, 20 * .mm)
			design.board.traces = [trace(joint, end)]
			var state = routing(from: start, to: joint)

			XCTAssertTrue(state.endTrace(in: &design))

			assertStraight(design.board)
			XCTAssertEqual(design.board.run(of: 0), Set(design.board.traces.indices))
			XCTAssertEqual(design.board.traces.count { $0.start == start || $0.end == start }, 1)
			XCTAssertEqual(design.board.traces.count { $0.start == end || $0.end == end }, 1)
		}
	}

	func testAnUnworkableFinishKeepsRoutingActiveAndLeavesTheBoardUnchanged() {
		var design = Design(board: Board(stack: .classic))
		let start = point(10 * .mm, 10 * .mm)
		let joint = point(20 * .mm, 10 * .mm)
		design.board.traces = [trace(joint, point(20 * .mm, 10_500))]
		let stored = design
		var state = routing(from: start, to: joint)

		XCTAssertFalse(state.endTrace(in: &design))

		XCTAssertEqual(design, stored)
		XCTAssertEqual(state.tool, .trace)
		XCTAssertEqual(state.traceSession?.start, start)
		XCTAssertEqual(state.traceSession?.end, joint)
		XCTAssertEqual(state.traceSession?.phase, .pending)
		XCTAssertEqual(state.traceSession?.anchors, [])
	}

	func testCopperOnAnotherLayerDoesNotFinishOrStraightenTheRoute() {
		var design = Design(board: Board(stack: .classic))
		let start = point(10 * .mm, 7 * .mm)
		let end = point(20 * .mm, 10 * .mm)
		let other = trace(end, point(30 * .mm, 10 * .mm), layer: 1)
		design.board.traces = [other]
		var state = routing(from: start, to: end)

		XCTAssertTrue(state.endTrace(in: &design))

		XCTAssertEqual(design.board.traces, [other, trace(start, end)])
		XCTAssertEqual(state.tool, .trace)
		XCTAssertEqual(state.traceSession?.start, end)
		XCTAssertEqual(state.traceSession?.anchors, [start])
		state.backtrackTrace(in: &design.board)
		XCTAssertEqual(design.board.traces, [other])
		XCTAssertEqual(state.traceSession?.start, start)
	}
}
