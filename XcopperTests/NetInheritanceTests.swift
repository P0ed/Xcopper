import XCTest
@testable import Xcopper

@MainActor
final class NetInheritanceTests: XCTestCase {

	private func point(_ x: Double, _ y: Double) -> Point { Point(x: .mm(x), y: .mm(y)) }
	private func trace(_ start: Point, _ end: Point, layer: Int = 0, net: Net.ID? = nil) -> Trace {
		Trace(start: start, end: end, width: .mm(0.4), layer: layer, net: net)
	}
	private func via(_ at: Point, from: Int = 0, to: Int = 1, net: Net.ID? = nil) -> Via {
		Via(at: at, drill: .mm(0.3), pad: .mm(0.6), from: from, to: to, net: net)
	}
	private func pad(_ at: Point, net: Net.ID?, through: Bool = false, flipped: Bool = false) -> Footprint {
		var footprint = Footprint(spec: .init(kind: .chip), reference: "R1", at: at)
		footprint.pads = [Pad(at: .zero, size: Size(width: .mm(1), height: .mm(1)),
			shape: .oval, drill: through ? .mm(0.3) : 0, layer: 0, name: "1", net: net)]
		footprint.flipped = flipped
		return footprint
	}

	func testConnectedChainInheritsFromAPadInOneUndoStep() {
		var design = Design(board: Board(stack: .classic))
		design.board.footprints = [pad(point(10, 10), net: 1)]
		design.board.traces = [trace(point(20, 10), point(30, 10), layer: 1)]
		design.board.vias = [via(point(20, 10))]
		let harness = EditorHarness(design: design)
		harness.perform { $0.design.board.traces.append(trace(point(10, 10), point(20, 10))) }
		let connected = harness.design
		XCTAssertEqual(connected.board.traces.map(\.net), [1, 1])
		XCTAssertEqual(connected.board.vias.map(\.net), [1])
		XCTAssertEqual(connected.board.footprints, design.board.footprints)
		harness.undo.undo()
		XCTAssertEqual(harness.design, design)
		harness.undo.redo()
		XCTAssertEqual(harness.design, connected)
	}

	func testTouchingTraceBodiesAndAViaInheritWithoutEndpointSnapping() {
		var design = Design(board: Board(stack: .classic))
		design.board.traces = [
			trace(point(10, 20), point(30, 20), net: 2),
			trace(point(20, 10), point(20, 30)),
		]
		design.board.vias = [via(point(15, 20.4))]
		design.inheritConnectedNets()
		XCTAssertEqual(design.board.traces.map(\.net), [2, 2])
		XCTAssertEqual(design.board.vias[0].net, 2)
	}

	func testAnAssignedViaPropagatesThroughUnassignedCopperRegardlessOfOrder() {
		var design = Design(board: Board(stack: .classic))
		design.board.traces = [
			trace(point(20, 10), point(30, 10)),
			trace(point(10, 10), point(20, 10)),
		]
		design.board.vias = [via(point(10, 10), net: 0)]
		var reversed = design
		reversed.board.traces.reverse()
		design.inheritConnectedNets()
		reversed.inheritConnectedNets()
		XCTAssertEqual(design.board.traces.map(\.net), [0, 0])
		XCTAssertEqual(reversed.board.traces.map(\.net), [0, 0])
	}

	func testLayerAndViaSpanLimitConnections() {
		var design = Design(board: Board(stack: .analog))
		design.board.traces = [
			trace(point(10, 20), point(30, 20), net: 1),
			trace(point(20, 10), point(20, 30), layer: 1),
		]
		design.board.vias = [via(point(15, 20), from: 1, to: 2)]
		design.inheritConnectedNets()
		XCTAssertNil(design.board.traces[1].net)
		XCTAssertNil(design.board.vias[0].net)
	}

	func testFlippedAndThroughHolePadsUseTheirCopperLayers() {
		for through in [false, true] {
			var design = Design(board: Board(stack: .classic))
			design.board.footprints = [pad(point(10, 10), net: 1, through: through, flipped: true)]
			design.board.traces = [
				trace(point(10, 10), point(20, 10)),
				trace(point(10, 10), point(20, 10), layer: 1),
			]
			design.inheritConnectedNets()
			XCTAssertEqual(design.board.traces[0].net, through ? 1 : nil)
			XCTAssertEqual(design.board.traces[1].net, 1)
		}
	}

	func testConflictingNetsStayAssignedAndLeaveTheConnectingTraceUnassigned() {
		var design = Design(board: Board(stack: .classic))
		design.board.traces = [
			trace(point(10, 10), point(20, 10), net: 1),
			trace(point(20, 10), point(30, 10)),
			trace(point(30, 10), point(40, 10), net: 2),
		]
		design.board.vias = [via(point(25, 10))]
		let original = design
		design.inheritConnectedNets()
		XCTAssertEqual(design, original)
	}

	func testNearbyCopperAndMechanicalHolesDoNotPropagateNets() {
		var design = Design(board: Board(stack: .classic))
		design.board.traces = [
			trace(point(10, 10), point(20, 10), net: 1),
			trace(point(10, 10.5), point(20, 10.5)),
		]
		design.board.holes = [Hole(at: point(15, 10.25), diameter: .mm(2))]
		design.board.vias = [via(point(40, 40))]
		let original = design
		design.inheritConnectedNets()
		XCTAssertEqual(design, original)
	}

	func testSchematicNetAssignmentReachesPreviouslyUnassignedCopper() {
		var design = Design(board: Board(stack: .classic))
		design.place(Symbol.Spec(kind: .resistor), at: point(20, 20))
		let at = design.board.footprints[0].placedPads[0].at
		design.board.vias = [via(at)]
		design.board.traces = [trace(at, at + point(0, 10), layer: 1)]
		let harness = EditorHarness(design: design)
		harness.perform {
			$0.design.schematic.labels = [NetLabel(at: design.schematic.symbols[0].placedPins[0].at, text: "SIGNAL")]
		}
		let signal = harness.design.board.footprints[0].pads[0].net
		XCTAssertNotNil(signal)
		XCTAssertEqual(harness.design.board.vias[0].net, signal)
		XCTAssertEqual(harness.design.board.traces[0].net, signal)
		XCTAssertNil(harness.design.board.footprints[0].pads[1].net)
	}

	func testMovingAnUnassignedViaOntoATraceInheritsItsNet() {
		var design = Design(board: Board(stack: .classic))
		design.board.traces = [trace(point(10, 20), point(30, 20), net: 2)]
		design.board.vias = [via(point(20, 40))]
		let harness = EditorHarness(design: design)
		harness.perform { $0.design.board.vias[0].at = point(20, 20) }
		XCTAssertEqual(harness.design.board.vias[0].net, 2)
		harness.undo.undo()
		XCTAssertEqual(harness.design, design)
	}
}
