import XCTest
@testable import Xcopper

enum ConnectionFixtures {
	static func design(_ stack: Stack = .classic, offGrid: Bool = false) -> Design {
		var design = Design(board: Board(size: Size(width: 20000, height: 12000), stack: stack))
		design.nets.append(Net(id: 3, name: "SIGNAL"))
		design.board.rules.traceWidth = 200
		design.board.rules.clearance = 200
		design.board.rules.viaPad = 900
		design.board.rules.viaDrill = 400
		design.board.footprints = [part("J1", at: Point(x: offGrid ? 4037 : 4000, y: offGrid ? 6091 : 6000)), part("J2", at: Point(x: offGrid ? 15961 : 16000, y: offGrid ? 6013 : 6000))]
		return design
	}

	static func part(_ reference: String, at: Point, net: Int = 3) -> Footprint {
		var symbol = Symbol.ic(pinNames: ["P"])
		symbol.pins[0].netLabel = net == 3 ? "SIGNAL" : "GND"
		return Footprint(reference: reference, value: "", at: at, rotation: .r0, flipped: false,
			pads: [Pad(at: .zero, size: Size(width: 800, height: 800), shape: .oval, drill: 0, layer: 0, name: "1", net: net)],
			body: Rect(center: .zero, size: Size(width: 1000, height: 1000)), symbol: symbol)
	}

	static func request(_ design: Design, layers: [Int] = [0], viaLimit: Int = 0) -> ConnectionRoutingRequest {
		let resolved = design.resolved
		let islands = resolved.board.connectivity(planes: resolved.planes).islands
		let from = islands.first { $0.terminals.contains { $0.ref == .pad(0, 0) } }!
		let to = islands.first { $0.terminals.contains { $0.ref == .pad(1, 0) } }!
		return ConnectionRoutingRequest(board: resolved.board, from: from, to: to, layers: layers, width: 200, clearance: 200, viaLimit: viaLimit, grid: 250)
	}
}

final class ConnectionRoutingTests: XCTestCase {
	private func candidate(_ original: Design, _ route: PlannedConnection) -> Design {
		var result = original
		result.board.traces.append(contentsOf: route.traces)
		result.board.vias.append(contentsOf: route.vias)
		return result
	}

	func testRoutesOffGridPadsAndCompletesNativeConnectivity() throws {
		let design = ConnectionFixtures.design(offGrid: true)
		let route = try ConnectionRouter(ConnectionFixtures.request(design)).plan()
		XCTAssertFalse(route.traces.isEmpty)
		XCTAssertTrue(route.traces.allSatisfy { ($0.end - $0.start).isOctilinear })
		XCTAssertEqual(candidate(design, route).check(), [])
	}

	func testAvoidsUnassignedCopperAndHolesUsingNativeDistances() throws {
		var design = ConnectionFixtures.design()
		design.board.traces = [Trace(start: Point(x: 10000, y: 3500), end: Point(x: 10000, y: 8500), width: 600, layer: 0)]
		design.board.holes = [Hole(at: Point(x: 10000, y: 2000), diameter: 1500)]
		let route = try ConnectionRouter(ConnectionFixtures.request(design)).plan()
		for trace in route.traces {
			let figure = Figure.segment(trace.start, trace.end, trace.width!)
			XCTAssertGreaterThanOrEqual(gap(figure, design.board.objects[0].figure), 199.5)
			XCTAssertGreaterThanOrEqual(gap(figure, .round(design.board.holes[0].at, 1500)), 199.5)
		}
		XCTAssertEqual(candidate(design, route).check(), [])
	}

	func testLayerChangesRespectViaLimitsAndPreserveExistingCopper() throws {
		var design = ConnectionFixtures.design()
		design.board.traces = [Trace(start: Point(x: 10000, y: 0), end: Point(x: 10000, y: 12000), width: 600, layer: 0, net: 1)]
		var request = ConnectionFixtures.request(design, layers: [0, 1], viaLimit: 2)
		request.grid = 500
		let route = try ConnectionRouter(request).plan()
		XCTAssertEqual(route.vias.count, 2)
		XCTAssertTrue(route.traces.contains { $0.layer == 1 })
		XCTAssertEqual(candidate(design, route).board.traces[0], design.board.traces[0])
		request.viaLimit = 0
		XCTAssertThrowsError(try ConnectionRouter(request).plan()) { XCTAssertEqual(($0 as? ConnectionRoutingFailure)?.code, "no_path") }
	}

	func testExistingIslandCopperCanBeUsedWithoutMovingIt() throws {
		var design = ConnectionFixtures.design()
		design.board.traces = [Trace(start: Point(x: 4000, y: 6000), end: Point(x: 11000, y: 6000), width: 200, layer: 0, net: 3)]
		let request = ConnectionFixtures.request(design)
		let route = try ConnectionRouter(request).plan()
		XCTAssertLessThan(route.length, 6000)
		XCTAssertEqual(candidate(design, route).check(), [])
		XCTAssertEqual(candidate(design, route).board.traces.first, design.board.traces.first)
	}

	func testPlaneConnectionAddsAViaAndSettlesNativePlaneDiagnostics() throws {
		var design = ConnectionFixtures.design(.digital)
		design.board.footprints = [ConnectionFixtures.part("J1", at: Point(x: 4000, y: 6000), net: 0)]
		let from = design.board.connectivity(planes: design.planes).islands[0]
		let request = ConnectionRoutingRequest(board: design.board, from: from, layers: [0], width: 200, clearance: 200, viaLimit: 1, grid: 250)
		let route = try ConnectionRouter(request).plan()
		XCTAssertEqual(route.vias.count, 1)
		XCTAssertEqual(candidate(design, route).check(), [])
	}

	func testBudgetExhaustionAndInvalidRulesHaveDistinctFailures() throws {
		let design = ConnectionFixtures.design()
		var request = ConnectionFixtures.request(design)
		request.maxNodes = 1
		XCTAssertThrowsError(try ConnectionRouter(request).plan()) { XCTAssertEqual(($0 as? ConnectionRoutingFailure)?.code, "search_exhausted") }
		request.clearance = 0
		XCTAssertThrowsError(try ConnectionRouter(request).plan()) { XCTAssertEqual(($0 as? ConnectionRoutingFailure)?.code, "invalid_rules") }
	}

	func testCancelledSearchReturnsCancellation() async throws {
		let request = ConnectionFixtures.request(ConnectionFixtures.design())
		let task = Task { try Task.checkCancellation(); return try ConnectionRouter(request).plan() }
		task.cancel()
		do { _ = try await task.value; XCTFail("Expected cancellation") }
		catch { XCTAssertTrue(error is CancellationError) }
	}

	func testCrossingSameNetCopperFormsOneIsland() {
		var design = ConnectionFixtures.design()
		design.board.traces = [Trace(start: Point(x: 4000, y: 6000), end: Point(x: 16000, y: 6000), width: 200, layer: 0, net: 3), Trace(start: Point(x: 10000, y: 2000), end: Point(x: 10000, y: 10000), width: 200, layer: 0, net: 3)]
		XCTAssertEqual(design.board.connectivity().islands.count, 1)
	}
}
