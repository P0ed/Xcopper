import XCTest
@testable import Xcopper

final class WireRoutingTests: XCTestCase {
	private func point(_ x: µm, _ y: µm) -> Point { Point(x: x, y: y) }
	private func wire(_ ax: µm, _ ay: µm, _ bx: µm, _ by: µm) -> Wire {
		Wire(start: point(ax, ay), end: point(bx, by))
	}
	private func footprint(at point: Point, reference: String = "R1") -> Footprint {
		var footprint = Footprint(symbol: .init(kind: .resistor), reference: reference, at: point)
		footprint.symbol.pins = [Pin(at: .zero, direction: .r0, length: 0, name: "1", number: "1")]
		return footprint
	}
	private func assertOrthogonal(_ schematic: Board, file: StaticString = #filePath, line: UInt = #line) {
		XCTAssertTrue(schematic.wires.allSatisfy {
			$0.start != $0.end && ($0.start.x == $0.end.x || $0.start.y == $0.end.y)
		}, file: file, line: line)
	}
	private func assertConnected(_ schematic: Board, _ a: Point, _ b: Point, file: StaticString = #filePath, line: UInt = #line) {
		let netlist = Netlist(schematic)
		XCTAssertNotNil(netlist.group(at: a), file: file, line: line)
		XCTAssertEqual(netlist.group(at: a)?.points, netlist.group(at: b)?.points, file: file, line: line)
	}

	func testDraggingTheBottomOfARectangularRunStretchesBothNeighbours() throws {
		var schematic = Board()
		schematic.wires = [wire(0, 0, 0, 10 * .mm), wire(0, 10 * .mm, 10 * .mm, 10 * .mm), wire(10 * .mm, 10 * .mm, 10 * .mm, 0)]
		let selection = try XCTUnwrap(schematic.moveSchematic([.wire(1)], by: point(3 * .mm, -4 * .mm), grid: 1 * .mm))
		XCTAssertEqual(schematic.wires, [wire(0, 0, 0, 6 * .mm), wire(0, 6 * .mm, 10 * .mm, 6 * .mm), wire(10 * .mm, 6 * .mm, 10 * .mm, 0)])
		XCTAssertEqual(selection, [.wire(1)])
		assertConnected(schematic, point(0, 0), point(10 * .mm, 0))
	}

	func testMovingASymbolSlidesTheNextCorner() throws {
		var schematic = Board()
		schematic.footprints = [footprint(at: .zero)]
		schematic.wires = [wire(0, 0, 10 * .mm, 0), wire(10 * .mm, 0, 10 * .mm, 10 * .mm)]
		XCTAssertNotNil(schematic.moveSchematic([.symbol(0)], by: point(2 * .mm, 3 * .mm)))
		XCTAssertEqual(schematic.wires, [wire(2 * .mm, 3 * .mm, 10 * .mm, 3 * .mm), wire(10 * .mm, 3 * .mm, 10 * .mm, 10 * .mm)])
		assertConnected(schematic, point(2 * .mm, 3 * .mm), point(10 * .mm, 10 * .mm))
		assertOrthogonal(schematic)
	}

	func testMovingASymbolFoldsAWireBetweenFixedPins() throws {
		for rotation in Rotation.allCases {
			var schematic = Board()
			schematic.footprints = [footprint(at: .zero), footprint(at: point(10 * .mm, 0), reference: "R2")]
			schematic.wires = [wire(0, 0, 10 * .mm, 0)]
			let delta = point(2 * .mm, 3 * .mm).rotated(rotation)
			XCTAssertNotNil(schematic.moveSchematic([.symbol(0)], by: delta))
			XCTAssertEqual(schematic.footprints[1].symbol.at, point(10 * .mm, 0))
			XCTAssertEqual(schematic.wires.count, 2)
			XCTAssertEqual(Netlist(schematic).group(at: delta)?.nodes,
				[.init(symbol: 0, pin: 0), .init(symbol: 1, pin: 0)])
			assertOrthogonal(schematic)
		}
	}

	func testMovingASegmentKeepsItsStationaryPinsAndNeighbourConnected() throws {
		var schematic = Board()
		schematic.footprints = [footprint(at: .zero), footprint(at: point(10 * .mm, 0), reference: "R2")]
		schematic.wires = [wire(0, 0, 10 * .mm, 0), wire(10 * .mm, 0, 10 * .mm, 10 * .mm)]
		XCTAssertNotNil(schematic.moveSchematic([.wire(0)], by: point(0, 3 * .mm)))
		assertConnected(schematic, .zero, point(10 * .mm, 10 * .mm))
		XCTAssertEqual(Netlist(schematic).group(at: .zero)?.nodes,
			[.init(symbol: 0, pin: 0), .init(symbol: 1, pin: 0)])
		assertOrthogonal(schematic)
	}

	func testDraggingAWireBetweenPinsIgnoresTravelAlongTheWire() throws {
		var schematic = Board()
		schematic.footprints = [footprint(at: .zero), footprint(at: point(10 * .mm, 0), reference: "R2")]
		schematic.wires = [wire(0, 0, 10 * .mm, 0)]
		XCTAssertNotNil(schematic.moveSchematic([.wire(0)], by: point(2 * .mm, 3 * .mm)))
		XCTAssertEqual(schematic.wires, [wire(0, 3 * .mm, 10 * .mm, 3 * .mm), wire(0, 0, 0, 3 * .mm), wire(10 * .mm, 0, 10 * .mm, 3 * .mm)])
		assertConnected(schematic, .zero, point(10 * .mm, 0))
		assertOrthogonal(schematic)
	}

	func testMovingAWireOrSymbolAtATJunctionKeepsAllThreeLegs() throws {
		for selected: SchematicRef in [.wire(1), .symbol(0)] {
			var schematic = Board()
			schematic.wires = [wire(0, 0, 10 * .mm, 0), wire(5 * .mm, 0, 5 * .mm, 10 * .mm)]
			if case .symbol = selected { schematic.footprints = [footprint(at: point(5 * .mm, 0))] }
			XCTAssertNotNil(schematic.moveSchematic([selected], by: point(2 * .mm, 3 * .mm)))
			assertConnected(schematic, point(0, 0), point(10 * .mm, 0))
			assertConnected(schematic, point(0, 0), selected == .wire(1) ? point(7 * .mm, 13 * .mm) : point(5 * .mm, 10 * .mm))
			assertOrthogonal(schematic)
		}
	}

	func testMovingAcrossAnUnconnectedCrossingDoesNotCarryTheOtherWire() throws {
		var schematic = Board()
		schematic.wires = [wire(0, 0, 10 * .mm, 0), wire(5 * .mm, -5 * .mm, 5 * .mm, 5 * .mm)]
		XCTAssertNotNil(schematic.moveSchematic([.wire(0)], by: point(0, 2 * .mm)))
		XCTAssertEqual(schematic.wires, [wire(0, 2 * .mm, 10 * .mm, 2 * .mm), wire(5 * .mm, -5 * .mm, 5 * .mm, 5 * .mm)])
		XCTAssertEqual(Netlist(schematic).groups.count, 2)
	}

	func testMovingAWireAndItsSymbolDoesNotMoveThePinTwice() throws {
		var schematic = Board()
		schematic.footprints = [footprint(at: .zero)]
		schematic.wires = [wire(0, 0, 10 * .mm, 0)]
		XCTAssertNotNil(schematic.moveSchematic([.symbol(0), .wire(0)], by: point(2 * .mm, 3 * .mm)))
		XCTAssertEqual(schematic.wires, [wire(2 * .mm, 3 * .mm, 12 * .mm, 3 * .mm)])
		assertConnected(schematic, point(2 * .mm, 3 * .mm), point(12 * .mm, 3 * .mm))
	}

	func testMovingALabelledPinOnTheMiddleOfAWireKeepsItsNetName() throws {
		var schematic = Board()
		schematic.wires = [wire(0, 0, 10 * .mm, 0)]
		schematic.footprints = [footprint(at: point(5 * .mm, 0))]
		schematic.footprints[0].symbol.pins[0].netLabel = "SIGNAL"
		XCTAssertNotNil(schematic.moveSchematic([.symbol(0)], by: point(0, 3 * .mm)))
		XCTAssertEqual(Netlist(schematic).name(at: .zero), "SIGNAL")
		XCTAssertEqual(Netlist(schematic).name(at: point(10 * .mm, 0)), "SIGNAL")
		assertOrthogonal(schematic)
	}

	func testDraggingALabelledPinKeepsTheWireOnIt() {
		for anchor in [point(0, 0), point(5 * .mm, 0), point(10 * .mm, 0)] {
			var schematic = Board()
			schematic.wires = [wire(0, 0, 10 * .mm, 0)]
			schematic.footprints = [footprint(at: anchor)]
			schematic.footprints[0].symbol.pins[0].netLabel = "GND"
			XCTAssertNotNil(schematic.moveSchematic([.symbol(0)], by: point(0, 3 * .mm)))
			XCTAssertEqual(schematic.footprints[0].symbol.placedPins[0].at, anchor + point(0, 3 * .mm))
			let fixed = anchor == .zero ? point(10 * .mm, 0) : .zero
			assertConnected(schematic, fixed, schematic.footprints[0].symbol.placedPins[0].at)
			if anchor == point(5 * .mm, 0) { assertConnected(schematic, .zero, point(10 * .mm, 0)) }
			XCTAssertEqual(Netlist(schematic).name(at: fixed), "GND")
			assertOrthogonal(schematic)
		}
	}

	func testCollapsedNeighbourIsRemovedAndSelectionIsRemapped() throws {
		var schematic = Board()
		schematic.wires = [wire(0, 0, 10 * .mm, 0), wire(10 * .mm, 0, 10 * .mm, 10 * .mm)]
		let selection = try XCTUnwrap(schematic.moveSchematic([.wire(0)], by: point(0, 10 * .mm)))
		XCTAssertEqual(schematic.wires, [wire(0, 10 * .mm, 10 * .mm, 10 * .mm)])
		XCTAssertEqual(selection, [.wire(0)])
	}

	func testWireRoutesToAnOffsetTargetWithAnOrthogonalPreviewAndCommit() throws {
		var state = SchematicState()
		state.tool = .wire
		state.beginWire(at: .zero)
		XCTAssertNil(state.endWire())
		state.hoverWire(to: point(10 * .mm, 0))
		state.hoverWire(to: point(10 * .mm, 3 * .mm))
		let preview = try XCTUnwrap(state.wireSession).wires
		XCTAssertEqual(preview, [wire(0, 0, 10 * .mm, 0), wire(10 * .mm, 0, 10 * .mm, 3 * .mm)])
		state.beginWire(at: point(10 * .mm, 3 * .mm))
		state.updateWire(to: point(10 * .mm, 3 * .mm))
		XCTAssertEqual(state.endWire(), preview)
		XCTAssertEqual(state.wireSession?.start, point(10 * .mm, 3 * .mm))
		state.beginWire(at: point(10 * .mm, 3 * .mm))
		XCTAssertNil(state.endWire())
	}

	func testWireSnapsToTheMiddleOfAnotherWireAndRecognizesConnections() {
		var schematic = Board()
		schematic.wires = [wire(0, 0, 20 * .mm, 0)]
		XCTAssertEqual(schematic.snapTarget(near: point(7 * .mm, 200), radius: 1 * .mm), point(7 * .mm, 0))
		XCTAssertTrue(schematic.isConnection(point(7 * .mm, 0)))
		XCTAssertFalse(schematic.isConnection(point(7 * .mm, 2 * .mm)))
		XCTAssertEqual(snapped90(from: .zero, to: point(-10 * .mm, 2 * .mm), after: point(1 * .mm, 0)), point(0, 2 * .mm))
	}

	func testWholeWireSelectionStopsAtBranchesAndRequiresTheWholeRunInsideABand() {
		var schematic = Board()
		schematic.wires = [wire(0, 0, 10 * .mm, 0), wire(10 * .mm, 0, 10 * .mm, 10 * .mm), wire(10 * .mm, 10 * .mm, 20 * .mm, 10 * .mm)]
		XCTAssertEqual(schematic.schematicRefs(at: point(5 * .mm, 0), tolerance: 1, whole: true), [.wire(0), .wire(1), .wire(2)])
		XCTAssertEqual(schematic.schematicRefs(in: Rect(from: point(-1 * .mm, -1 * .mm), to: point(11 * .mm, 5 * .mm)), whole: true), [])
		schematic.wires.append(wire(10 * .mm, 0, 20 * .mm, 0))
		XCTAssertEqual(schematic.schematicRefs(at: point(5 * .mm, 0), tolerance: 1, whole: true), [.wire(0)])
	}
}
