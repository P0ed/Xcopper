import MCPS
import XCTest
@testable import Xcopper

@MainActor
final class MCPConnectionTests: XCTestCase {
	func testPlanningIsReadOnlyAndApplyingUsesTheExactPreviewInOneUndoStep() async throws {
		let fixture = MCPHarness(ConnectionFixtures.design(offGrid: true))
		fixture.editor.layout.selection = [.footprint(0)]
		let layout = fixture.editor.layout, original = fixture.editor.design
		let diagnostics = try fixture.entry.diagnostics()
		let connection = try XCTUnwrap(diagnostics.objectValue?["connections"]?.arrayValue?.first?.objectValue?["id"])
		let proposal = try await MCPTools.planConnection(fixture.args(["connection": connection, "layers": [0]]), entry: fixture.entry)
		XCTAssertEqual(fixture.editor.design, original)
		XCTAssertEqual(fixture.editor.layout, layout)
		XCTAssertEqual(fixture.entry.revision, 1)
		XCTAssertFalse(fixture.editor.undo.canUndo)
		let preview = try MCPTools.renderDesign(MCPArguments(["view": "layout", "layers": [0], "width": 256, "height": 192, "proposalId": proposal.objectValue!["proposalId"]!]), entry: fixture.entry)
		let proposedTraces = try JSONDecoder().decode([Trace].self, from: JSONEncoder().encode(proposal.objectValue!["traces"]!))
		_ = try MCPTools.applyConnection(fixture.args(["proposalId": proposal.objectValue!["proposalId"]!]), entry: fixture.entry)
		XCTAssertEqual(fixture.editor.design.board.traces, proposedTraces)
		XCTAssertEqual(fixture.editor.design.check(), [])
		let committedPreview = try MCPTools.renderDesign(MCPArguments(["view": "layout", "layers": [0], "width": 256, "height": 192]), entry: fixture.entry)
		XCTAssertEqual(committedPreview.objectValue?["imageData"], preview.objectValue?["imageData"])
		fixture.editor.undo.undo()
		fixture.entry.refresh()
		XCTAssertEqual(fixture.editor.design, original)
		XCTAssertFalse(fixture.editor.undo.canUndo)
	}

	func testInterveningEditsRejectAStaleProposal() async throws {
		let fixture = MCPHarness(ConnectionFixtures.design())
		let proposal = try await MCPTools.planConnection(fixture.args(["from": .string(fixture.entry.handle(.pad(0, 0))), "to": .string(fixture.entry.handle(.pad(1, 0)))]), entry: fixture.entry)
		let apply = fixture.args(["proposalId": proposal.objectValue!["proposalId"]!])
		fixture.editor.design.board.holes.append(Hole(at: Point(x: 10000, y: 10000), diameter: 1000))
		XCTAssertThrowsError(try MCPTools.applyConnection(apply, entry: fixture.entry)) { XCTAssertEqual(($0 as? MCPFailure)?.code, "stale_revision") }
		XCTAssertTrue(fixture.editor.design.board.traces.isEmpty)
		XCTAssertTrue(fixture.entry.proposals.isEmpty)
	}

	func testExpiredProposalsCannotBeApplied() async throws {
		let fixture = MCPHarness(ConnectionFixtures.design())
		let original = fixture.editor.design
		let proposal = try await MCPTools.planConnection(fixture.args(["from": .string(fixture.entry.handle(.pad(0, 0))), "to": .string(fixture.entry.handle(.pad(1, 0)))]), entry: fixture.entry)
		let id = try XCTUnwrap(fixture.entry.proposals.keys.first)
		fixture.entry.proposals[id]?.created = Date(timeIntervalSinceNow: -601)
		XCTAssertThrowsError(try MCPTools.applyConnection(fixture.args(["proposalId": proposal.objectValue!["proposalId"]!]), entry: fixture.entry)) { XCTAssertEqual(($0 as? MCPFailure)?.code, "invalid_proposal") }
		XCTAssertEqual(fixture.editor.design, original)
		XCTAssertFalse(fixture.editor.undo.canUndo)
	}

	func testUnrelatedPhysicalFaultsAndUnroutedNetsDoNotBlockAConnection() async throws {
		var design = ConnectionFixtures.design()
		design.board.traces = [Trace(start: Point(x: 0, y: 1000), end: Point(x: 2000, y: 1000), width: 200, layer: 0, net: 1)]
		design.board.footprints += [ConnectionFixtures.part("J3", at: Point(x: 3000, y: 3000), net: 0), ConnectionFixtures.part("J4", at: Point(x: 17000, y: 3000), net: 0)]
		let fixture = MCPHarness(design)
		let proposal = try await MCPTools.planConnection(fixture.args(["from": .string(fixture.entry.handle(.pad(0, 0))), "to": .string(fixture.entry.handle(.pad(1, 0)))]), entry: fixture.entry)
		XCTAssertFalse(proposal.objectValue!["violations"]!.arrayValue!.isEmpty)
		_ = try MCPTools.applyConnection(fixture.args(["proposalId": proposal.objectValue!["proposalId"]!]), entry: fixture.entry)
		XCTAssertEqual(fixture.editor.design.faults().count, design.faults().count)
		XCTAssertEqual(fixture.editor.design.board.traces.first, design.board.traces.first)
		XCTAssertTrue(fixture.editor.design.check().contains { $0.kind == .unrouted })
	}

	func testIncompatibleNetsAndMissingPlanesAreRejectedBeforeSearching() async throws {
		var design = ConnectionFixtures.design()
		design.board.footprints[1].pads[0].net = 0
		let fixture = MCPHarness(design)
		do {
			_ = try await MCPTools.planConnection(fixture.args(["from": .string(fixture.entry.handle(.pad(0, 0))), "to": .string(fixture.entry.handle(.pad(1, 0)))]), entry: fixture.entry)
			XCTFail("Expected incompatible nets")
		} catch { XCTAssertEqual((error as? MCPFailure)?.code, "incompatible_nets") }
		do {
			_ = try await MCPTools.planConnection(fixture.args(["from": .string(fixture.entry.handle(.pad(0, 0))), "to": "plane"]), entry: fixture.entry)
			XCTFail("Expected missing plane")
		} catch { XCTAssertEqual((error as? MCPFailure)?.code, "invalid_endpoint") }
	}

	func testImportedCopperIsAnObstacleAndStaysUnchangedWhenApplied() async throws {
		let root = URL(fileURLWithPath: "/tmp/xcopper-mcp-imported-route")
		var source = Design(board: Board(size: Size(width: 4000, height: 12000), stack: .classic))
		source.board.traces = [Trace(start: Point(x: 2000, y: 0), end: Point(x: 2000, y: 12000), width: 600, layer: 0, net: 1)]
		let data = try JSONEncoder().encode(source)
		var design = ConnectionFixtures.design()
		_ = try design.importModule(filename: "Wall.pcb", documentURL: root.appendingPathComponent("Parent.pcb"), library: ModuleLibrary(sources: [root.appendingPathComponent("Wall.pcb")]), read: { _ in data })
		design.modules[0].layoutAt = Point(x: 10000, y: 6000)
		let imported = design.resolved.board.traces
		let fixture = MCPHarness(design)
		let proposal = try await MCPTools.planConnection(fixture.args(["from": .string(fixture.entry.handle(.pad(0, 0))), "to": .string(fixture.entry.handle(.pad(1, 0))), "layers": [0, 1], "grid": 500, "viaLimit": 2]), entry: fixture.entry)
		XCTAssertEqual(proposal.objectValue?["vias"]?.arrayValue?.count, 2)
		_ = try MCPTools.applyConnection(fixture.args(["proposalId": proposal.objectValue!["proposalId"]!]), entry: fixture.entry)
		XCTAssertEqual(Array(fixture.editor.design.resolved.board.traces.suffix(imported.count)), imported)
		XCTAssertEqual(fixture.editor.design.modules, design.modules)
		XCTAssertEqual(fixture.editor.design.moduleCache, design.moduleCache)
	}
}
