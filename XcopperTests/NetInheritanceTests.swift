import XCTest
@testable import Xcopper

@MainActor
final class NetInheritanceTests: XCTestCase {

	private func point(_ x: µm, _ y: µm) -> Point { Point(x: x, y: y) }
	private func trace(_ start: Point, _ end: Point, layer: Int = 0, net: Net.ID? = nil) -> Trace {
		Trace(start: start, end: end, width: 400, layer: layer, net: net)
	}
	private func via(_ at: Point, net: Net.ID? = nil) -> Via {
		Via(at: at, net: net)
	}
	private func pad(_ at: Point, net: Net.ID?, through: Bool = false, flipped: Bool = false) -> Footprint {
		var footprint = Footprint(spec: .init(kind: .chip), reference: "R1", at: at)
		footprint.pads = [Pad(at: .zero, size: Size(width: 1 * .mm, height: 1 * .mm),
			shape: .oval, drill: through ? 300 : 0, layer: 0, name: "1", net: net)]
		footprint.flipped = flipped
		return footprint
	}

	func testConnectedChainInheritsFromAPadInOneUndoStep() {
		var design = Design(board: Board(stack: .classic))
		design.board.footprints = [pad(point(10 * .mm, 10 * .mm), net: 1)]
		design.board.traces = [trace(point(20 * .mm, 10 * .mm), point(30 * .mm, 10 * .mm), layer: 1)]
		design.board.vias = [via(point(20 * .mm, 10 * .mm))]
		let harness = EditorHarness(design: design)
		harness.perform { $0.design.board.traces.append(trace(point(10 * .mm, 10 * .mm), point(20 * .mm, 10 * .mm))) }
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
			trace(point(10 * .mm, 20 * .mm), point(30 * .mm, 20 * .mm), net: 2),
			trace(point(20 * .mm, 10 * .mm), point(20 * .mm, 30 * .mm)),
		]
		design.board.vias = [via(point(15 * .mm, 20_400))]
		design.inheritConnectedNets()
		XCTAssertEqual(design.board.traces.map(\.net), [2, 2])
		XCTAssertEqual(design.board.vias[0].net, 2)
	}

	func testAnAssignedViaPropagatesThroughUnassignedCopperRegardlessOfOrder() {
		var design = Design(board: Board(stack: .classic))
		design.board.traces = [
			trace(point(20 * .mm, 10 * .mm), point(30 * .mm, 10 * .mm)),
			trace(point(10 * .mm, 10 * .mm), point(20 * .mm, 10 * .mm)),
		]
		design.board.vias = [via(point(10 * .mm, 10 * .mm), net: 0)]
		var reversed = design
		reversed.board.traces.reverse()
		design.inheritConnectedNets()
		reversed.inheritConnectedNets()
		XCTAssertEqual(design.board.traces.map(\.net), [0, 0])
		XCTAssertEqual(reversed.board.traces.map(\.net), [0, 0])
	}

	func testCopperLayersStaySeparateUntilAViaConnectsThem() {
		var design = Design(board: Board(stack: .analog))
		design.board.traces = [
			trace(point(10 * .mm, 20 * .mm), point(30 * .mm, 20 * .mm), net: 1),
			trace(point(20 * .mm, 10 * .mm), point(20 * .mm, 30 * .mm), layer: design.board.stack.bottom),
		]
		design.inheritConnectedNets()
		XCTAssertNil(design.board.traces[1].net)
		design.board.vias = [via(point(20 * .mm, 20 * .mm))]
		design.inheritConnectedNets()
		XCTAssertEqual(design.board.traces[1].net, 1)
		XCTAssertEqual(design.board.vias[0].net, 1)
	}

	func testFlippedAndThroughHolePadsUseTheirCopperLayers() {
		for through in [false, true] {
			var design = Design(board: Board(stack: .classic))
			design.board.footprints = [pad(point(10 * .mm, 10 * .mm), net: 1, through: through, flipped: true)]
			design.board.traces = [
				trace(point(10 * .mm, 10 * .mm), point(20 * .mm, 10 * .mm)),
				trace(point(10 * .mm, 10 * .mm), point(20 * .mm, 10 * .mm), layer: 1),
			]
			design.inheritConnectedNets()
			XCTAssertEqual(design.board.traces[0].net, through ? 1 : nil)
			XCTAssertEqual(design.board.traces[1].net, 1)
		}
	}

	func testConflictingNetsStayAssignedAndLeaveTheConnectingTraceUnassigned() {
		var design = Design(board: Board(stack: .classic))
		design.board.traces = [
			trace(point(10 * .mm, 10 * .mm), point(20 * .mm, 10 * .mm), net: 1),
			trace(point(20 * .mm, 10 * .mm), point(30 * .mm, 10 * .mm)),
			trace(point(30 * .mm, 10 * .mm), point(40 * .mm, 10 * .mm), net: 2),
		]
		design.board.vias = [via(point(25 * .mm, 10 * .mm))]
		let original = design
		design.inheritConnectedNets()
		XCTAssertEqual(design, original)
	}

	func testNearbyCopperAndMechanicalHolesDoNotPropagateNets() {
		var design = Design(board: Board(stack: .classic))
		design.board.traces = [
			trace(point(10 * .mm, 10 * .mm), point(20 * .mm, 10 * .mm), net: 1),
			trace(point(10 * .mm, 10_500), point(20 * .mm, 10_500)),
		]
		design.board.holes = [Hole(at: point(15 * .mm, 10_250), diameter: 2 * .mm)]
		design.board.vias = [via(point(40 * .mm, 40 * .mm))]
		let original = design
		design.inheritConnectedNets()
		XCTAssertEqual(design, original)
	}

	func testSchematicNetAssignmentReachesPreviouslyUnassignedCopper() {
		var design = Design(board: Board(stack: .classic))
		design.place(Symbol.Spec(kind: .resistor), at: point(20 * .mm, 20 * .mm))
		let at = design.board.footprints[0].placedPads[0].at
		design.board.vias = [via(at)]
		design.board.traces = [trace(at, at + point(0, 10 * .mm), layer: 1)]
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
		design.board.traces = [trace(point(10 * .mm, 20 * .mm), point(30 * .mm, 20 * .mm), net: 2)]
		design.board.vias = [via(point(20 * .mm, 40 * .mm))]
		let harness = EditorHarness(design: design)
		harness.perform { $0.design.board.vias[0].at = point(20 * .mm, 20 * .mm) }
		XCTAssertEqual(harness.design.board.vias[0].net, 2)
		harness.undo.undo()
		XCTAssertEqual(harness.design, design)
	}
}
