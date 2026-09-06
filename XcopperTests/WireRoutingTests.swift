import XCTest
@testable import Xcopper

final class WireRoutingTests: XCTestCase {
	private func point(_ x: Double, _ y: Double) -> Point { Point(x: .mm(x), y: .mm(y)) }
	private func wire(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Wire {
		Wire(start: point(ax, ay), end: point(bx, by))
	}
	private func symbol(at point: Point, reference: String = "R1") -> Symbol {
		var symbol = Symbol(spec: .init(kind: .resistor), reference: reference, at: point)
		symbol.pins = [Pin(at: .zero, direction: .r0, length: 0, name: "1", number: "1")]
		return symbol
	}
	private func assertOrthogonal(_ schematic: Schematic, file: StaticString = #filePath, line: UInt = #line) {
		XCTAssertTrue(schematic.wires.allSatisfy {
			$0.start != $0.end && ($0.start.x == $0.end.x || $0.start.y == $0.end.y)
		}, file: file, line: line)
	}
	private func assertConnected(_ schematic: Schematic, _ a: Point, _ b: Point, file: StaticString = #filePath, line: UInt = #line) {
		let netlist = Netlist(schematic)
		XCTAssertNotNil(netlist.group(at: a), file: file, line: line)
		XCTAssertEqual(netlist.group(at: a)?.points, netlist.group(at: b)?.points, file: file, line: line)
	}

	func testDraggingTheBottomOfARectangularRunStretchesBothNeighbours() throws {
		var schematic = Schematic()
		schematic.wires = [wire(0, 0, 0, 10), wire(0, 10, 10, 10), wire(10, 10, 10, 0)]
		let selection = try XCTUnwrap(schematic.move([.wire(1)], by: point(3, -4), grid: .mm(1)))
		XCTAssertEqual(schematic.wires, [wire(0, 0, 0, 6), wire(0, 6, 10, 6), wire(10, 6, 10, 0)])
		XCTAssertEqual(selection, [.wire(1)])
		assertConnected(schematic, point(0, 0), point(10, 0))
	}

	func testMovingASymbolSlidesTheNextCorner() throws {
		var schematic = Schematic()
		schematic.symbols = [symbol(at: .zero)]
		schematic.wires = [wire(0, 0, 10, 0), wire(10, 0, 10, 10)]
		XCTAssertNotNil(schematic.move([.symbol(0)], by: point(2, 3)))
		XCTAssertEqual(schematic.wires, [wire(2, 3, 10, 3), wire(10, 3, 10, 10)])
		assertConnected(schematic, point(2, 3), point(10, 10))
		assertOrthogonal(schematic)
	}

	func testMovingASymbolFoldsAWireBetweenFixedPins() throws {
		for rotation in Rotation.allCases {
			var schematic = Schematic()
			schematic.symbols = [symbol(at: .zero), symbol(at: point(10, 0), reference: "R2")]
			schematic.wires = [wire(0, 0, 10, 0)]
			let delta = point(2, 3).rotated(rotation)
			XCTAssertNotNil(schematic.move([.symbol(0)], by: delta))
			XCTAssertEqual(schematic.symbols[1].at, point(10, 0))
			XCTAssertEqual(schematic.wires.count, 2)
			XCTAssertEqual(Netlist(schematic).group(at: delta)?.nodes,
				[.init(symbol: 0, pin: 0), .init(symbol: 1, pin: 0)])
			assertOrthogonal(schematic)
		}
	}

	func testMovingASegmentKeepsItsStationaryPinsAndNeighbourConnected() throws {
		var schematic = Schematic()
		schematic.symbols = [symbol(at: .zero), symbol(at: point(10, 0), reference: "R2")]
		schematic.wires = [wire(0, 0, 10, 0), wire(10, 0, 10, 10)]
		XCTAssertNotNil(schematic.move([.wire(0)], by: point(0, 3)))
		assertConnected(schematic, .zero, point(10, 10))
		XCTAssertEqual(Netlist(schematic).group(at: .zero)?.nodes,
			[.init(symbol: 0, pin: 0), .init(symbol: 1, pin: 0)])
		assertOrthogonal(schematic)
	}

	func testDraggingAWireBetweenPinsIgnoresTravelAlongTheWire() throws {
		var schematic = Schematic()
		schematic.symbols = [symbol(at: .zero), symbol(at: point(10, 0), reference: "R2")]
		schematic.wires = [wire(0, 0, 10, 0)]
		XCTAssertNotNil(schematic.move([.wire(0)], by: point(2, 3)))
		XCTAssertEqual(schematic.wires, [wire(0, 3, 10, 3), wire(0, 0, 0, 3), wire(10, 0, 10, 3)])
		assertConnected(schematic, .zero, point(10, 0))
		assertOrthogonal(schematic)
	}

	func testMovingAWireOrSymbolAtATJunctionKeepsAllThreeLegs() throws {
		for selected: Schematic.Ref in [.wire(1), .symbol(0)] {
			var schematic = Schematic()
			schematic.wires = [wire(0, 0, 10, 0), wire(5, 0, 5, 10)]
			if case .symbol = selected { schematic.symbols = [symbol(at: point(5, 0))] }
			XCTAssertNotNil(schematic.move([selected], by: point(2, 3)))
			assertConnected(schematic, point(0, 0), point(10, 0))
			assertConnected(schematic, point(0, 0), selected == .wire(1) ? point(7, 13) : point(5, 10))
			assertOrthogonal(schematic)
		}
	}

	func testMovingAcrossAnUnconnectedCrossingDoesNotCarryTheOtherWire() throws {
		var schematic = Schematic()
		schematic.wires = [wire(0, 0, 10, 0), wire(5, -5, 5, 5)]
		XCTAssertNotNil(schematic.move([.wire(0)], by: point(0, 2)))
		XCTAssertEqual(schematic.wires, [wire(0, 2, 10, 2), wire(5, -5, 5, 5)])
		XCTAssertEqual(Netlist(schematic).groups.count, 2)
	}

	func testMovingAWireAndItsSymbolDoesNotMoveThePinTwice() throws {
		var schematic = Schematic()
		schematic.symbols = [symbol(at: .zero)]
		schematic.wires = [wire(0, 0, 10, 0)]
		XCTAssertNotNil(schematic.move([.symbol(0), .wire(0)], by: point(2, 3)))
		XCTAssertEqual(schematic.wires, [wire(2, 3, 12, 3)])
		assertConnected(schematic, point(2, 3), point(12, 3))
	}

	func testMovingALabelOnTheMiddleOfAWireKeepsItsNetName() throws {
		var schematic = Schematic()
		schematic.wires = [wire(0, 0, 10, 0)]
		schematic.labels = [NetLabel(at: point(5, 0), text: "SIGNAL")]
		XCTAssertNotNil(schematic.move([.label(0)], by: point(0, 3)))
		XCTAssertEqual(Netlist(schematic).name(at: .zero), "SIGNAL")
		XCTAssertEqual(Netlist(schematic).name(at: point(10, 0)), "SIGNAL")
		assertOrthogonal(schematic)
	}

	func testCollapsedNeighbourIsRemovedAndSelectionIsRemapped() throws {
		var schematic = Schematic()
		schematic.wires = [wire(0, 0, 10, 0), wire(10, 0, 10, 10)]
		let selection = try XCTUnwrap(schematic.move([.wire(0)], by: point(0, 10)))
		XCTAssertEqual(schematic.wires, [wire(0, 10, 10, 10)])
		XCTAssertEqual(selection, [.wire(0)])
	}

	func testWireRoutesToAnOffsetTargetWithAnOrthogonalPreviewAndCommit() throws {
		var state = SchematicState()
		state.tool = .wire
		state.beginWire(at: .zero)
		XCTAssertNil(state.endWire())
		state.hoverWire(to: point(10, 0))
		state.hoverWire(to: point(10, 3))
		let preview = try XCTUnwrap(state.wireSession).wires
		XCTAssertEqual(preview, [wire(0, 0, 10, 0), wire(10, 0, 10, 3)])
		state.beginWire(at: point(10, 3))
		state.updateWire(to: point(10, 3))
		XCTAssertEqual(state.endWire(), preview)
		XCTAssertEqual(state.wireSession?.start, point(10, 3))
		state.beginWire(at: point(10, 3))
		XCTAssertNil(state.endWire())
	}

	func testWireSnapsToTheMiddleOfAnotherWireAndRecognizesConnections() {
		var schematic = Schematic()
		schematic.wires = [wire(0, 0, 20, 0)]
		XCTAssertEqual(schematic.snapTarget(near: point(7, 0.2), radius: .mm(1)), point(7, 0))
		XCTAssertTrue(schematic.isConnection(point(7, 0)))
		XCTAssertFalse(schematic.isConnection(point(7, 2)))
		XCTAssertEqual(snapped90(from: .zero, to: point(-10, 2), after: point(1, 0)), point(0, 2))
	}

	func testWholeWireSelectionStopsAtBranchesAndRequiresTheWholeRunInsideABand() {
		var schematic = Schematic()
		schematic.wires = [wire(0, 0, 10, 0), wire(10, 0, 10, 10), wire(10, 10, 20, 10)]
		XCTAssertEqual(schematic.refs(at: point(5, 0), tolerance: 1, whole: true), [.wire(0), .wire(1), .wire(2)])
		XCTAssertEqual(schematic.refs(in: Rect(from: point(-1, -1), to: point(11, 5)), whole: true), [])
		schematic.wires.append(wire(10, 0, 20, 0))
		XCTAssertEqual(schematic.refs(at: point(5, 0), tolerance: 1, whole: true), [.wire(0)])
	}
}
