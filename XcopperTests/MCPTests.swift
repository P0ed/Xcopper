import AppKit
import MCPS
import SwiftUI
import XCTest
@testable import Xcopper

@MainActor
final class MCPHarness {
	let editor: EditorHarness
	let native = NSDocument()
	let entry: MCPDocumentEntry
	init(_ design: Design = Design()) {
		editor = EditorHarness(design: design)
		entry = MCPDocumentEntry(id: UUID(), native: native, design: design)
		entry.contexts[ObjectIdentifier(native)] = .init(design: editor.operations.$design, operations: editor.operations, undoManager: editor.undo)
	}
	func args(_ fields: [String: MCPJSON] = [:]) -> MCPArguments {
		var fields = fields
		entry.refresh()
		fields["documentId"] = .string(entry.id.uuidString)
		fields["expectedRevision"] = .int(entry.revision)
		return MCPArguments(fields)
	}
	func batch(_ operations: [MCPJSON], dryRun: Bool = false) throws -> MCPJSON {
		try MCPTools.performEdits("apply_edits", args(["operations": .array(operations), "dryRun": .bool(dryRun)]), entry: entry)
	}
}

@MainActor
final class MCPTests: XCTestCase {
	private func placement(_ reference: String = "R1", id: String = "r", x: Int = 10000) -> MCPJSON {
		["id": .string(id), "tool": "place_part", "arguments": ["spec": ["symbolKind": "resistor"], "view": "layout", "at": ["x": .int(x), "y": 10000], "reference": .string(reference), "value": "10k", "labels": ["1": "IN", "2": "BUS"]]]
	}

	func testBatchAliasesSynchronizeConnectivityAndUndoAsOneAction() throws {
		let fixture = MCPHarness()
		let original = fixture.editor.design
		let result = try fixture.batch([placement(), ["tool": "update_part", "arguments": ["object": "$r", "value": "22k"]]])
		XCTAssertEqual(fixture.entry.revision, 2)
		XCTAssertEqual(fixture.editor.design.board.footprints[0].value, "22k")
		let nets = fixture.editor.design.board.footprints[0].pads.compactMap { fixture.editor.design.net($0.net)?.name }
		XCTAssertEqual(Set(nets), ["IN", "BUS"])
		XCTAssertEqual(result.objectValue?["results"]?.objectValue?["r"]?.stringValue, fixture.entry.handle("part", "0"))
		let committed = fixture.editor.design
		fixture.editor.undo.undo()
		fixture.entry.refresh()
		XCTAssertEqual(fixture.editor.design, original)
		XCTAssertFalse(fixture.editor.undo.canUndo)
		fixture.editor.undo.redo()
		fixture.entry.refresh()
		XCTAssertEqual(fixture.editor.design, committed)
		XCTAssertEqual(fixture.entry.revision, 4)
	}

	func testFailedBatchReportsTheOperationWithoutChangingDesignHistoryOrRevision() throws {
		let fixture = MCPHarness()
		let original = fixture.editor.design
		XCTAssertThrowsError(try fixture.batch([placement(), ["id": "bad", "tool": "set_pin_labels", "arguments": ["object": "$r", "labels": ["999": "X"]]]])) { error in
			XCTAssertEqual((error as? MCPFailure)?.code, "unknown_pin")
			XCTAssertEqual((error as? MCPFailure)?.details["operationIndex"], 1)
			XCTAssertEqual((error as? MCPFailure)?.details["operationId"], "bad")
		}
		XCTAssertEqual(fixture.editor.design, original)
		XCTAssertEqual(fixture.entry.revision, 1)
		XCTAssertFalse(fixture.editor.undo.canUndo)
	}

	func testDryRunDoesNotChangeEditorStateOrAllocateLiveHandles() throws {
		let fixture = MCPHarness()
		fixture.editor.layout.selection = [.trace(99)]
		let state = fixture.editor.layout
		let original = fixture.editor.design
		let result = try fixture.batch([placement()], dryRun: true)
		XCTAssertEqual(fixture.editor.design, original)
		XCTAssertEqual(fixture.editor.layout, state)
		XCTAssertEqual(fixture.entry.revision, 1)
		XCTAssertFalse(fixture.editor.undo.canUndo)
		XCTAssertEqual(result.objectValue?["preview"]?.objectValue?["parts"]?.arrayValue?.count, 1)
		let json = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
		XCTAssertFalse(json.contains(fixture.entry.id.uuidString + ":"))
	}

	func testAliasesAndOriginalHandlesFollowDeletionReindexing() throws {
		var design = Design()
		design.board.vias = [Via(at: Point(x: 10000, y: 10000)), Via(at: Point(x: 20000, y: 10000))]
		let fixture = MCPHarness(design)
		let first = fixture.entry.handle("via", "0"), second = fixture.entry.handle("via", "1")
		_ = try fixture.batch([
			["id": "new", "tool": "place_via", "arguments": ["at": ["x": 30000, "y": 10000]]],
			["tool": "delete_objects", "arguments": ["view": "layout", "objects": [.string(first)]]],
			["tool": "update_objects", "arguments": ["updates": [["object": .string(second), "net": "SIGNAL"], ["object": "$new", "net": "RETURN"]]]]
		])
		XCTAssertEqual(fixture.editor.design.board.vias.map(\.at.x), [20000, 30000])
		XCTAssertEqual(fixture.editor.design.board.vias.compactMap { fixture.editor.design.net($0.net)?.name }, ["SIGNAL", "RETURN"])
	}

	func testATraceConsumedByFusionCannotSilentlyTargetAnotherObject() throws {
		var design = Design()
		design.board.traces = [Trace(start: Point(x: 10000, y: 10000), end: Point(x: 20000, y: 10000), layer: 0)]
		let fixture = MCPHarness(design)
		XCTAssertThrowsError(try fixture.batch([
			["tool": "route_traces", "arguments": ["points": [["x": 20000, "y": 10000], ["x": 30000, "y": 10000]], "layer": 0]],
			["tool": "update_objects", "arguments": ["updates": [["object": .string(fixture.entry.handle("trace", "0")), "width": 800]]]]
		])) { XCTAssertEqual(($0 as? MCPFailure)?.code, "invalid_object") }
		XCTAssertEqual(fixture.editor.design, design)
	}

	func testStaleRevisionsAndSideEffectingBatchToolsAreRejected() throws {
		let fixture = MCPHarness()
		let stale = fixture.args(["operations": [placement()]])
		_ = try fixture.batch([placement()])
		XCTAssertThrowsError(try MCPTools.performEdits("apply_edits", stale, entry: fixture.entry)) { XCTAssertEqual(($0 as? MCPFailure)?.code, "stale_revision") }
		XCTAssertThrowsError(try fixture.batch([["tool": "save_document", "arguments": [:]]])) { XCTAssertEqual(($0 as? MCPFailure)?.code, "invalid_operation") }
	}

	func testCompactResponseAndFilteredInspectionContainOnlyRelevantObjects() throws {
		let fixture = MCPHarness()
		_ = try fixture.batch([placement("R1", id: "a"), placement("R2", id: "b", x: 20000)])
		let response = try MCPTools.performEdits("update_part", fixture.args(["object": .string(fixture.entry.handle("part", "0")), "value": "47k", "response": "compact"]), entry: fixture.entry)
		XCTAssertEqual(response.objectValue?["changes"]?.objectValue?["updated"]?.arrayValue?.count, 1)
		XCTAssertEqual(response.objectValue?["changes"]?.objectValue?["created"]?.arrayValue, [])
		let filtered = MCPTools.filterInspection(try fixture.entry.inspection(), MCPArguments(["sections": ["parts"], "references": ["R2"], "nets": ["BUS"]]))
		XCTAssertNil(filtered.objectValue?["traces"])
		XCTAssertEqual(filtered.objectValue?["parts"]?.arrayValue?.map { $0.objectValue?["reference"] }, ["R2"])
	}

	func testBatchReducesRoundTripsAndResponseBytes() throws {
		let singles = MCPHarness(), batched = MCPHarness()
		var operations: [MCPJSON] = [], bytes = 0
		func perform(_ name: String, _ fields: [String: MCPJSON]) throws {
			let result = try MCPTools.performEdits(name, singles.args(fields), entry: singles.entry)
			bytes += try JSONEncoder().encode(result).count
			operations.append(["tool": .string(name), "arguments": .object(fields)])
		}
		for index in 0 ..< 12 {
			let placement = placement("R\(index + 1)", id: "r\(index)", x: 5000 + index * 6000)
			try perform("place_part", placement.objectValue!["arguments"]!.objectValue!)
		}
		var last: Point?
		for part in singles.editor.design.board.footprints {
			let pad = try XCTUnwrap(part.placedPads.first { $0.name == "2" })
			let via = pad.at + Point(x: 0, y: 3000)
			try perform("route_traces", ["points": try MCPJSON([pad.at, via]), "layer": 0, "net": "BUS"])
			try perform("place_via", ["at": try MCPJSON(via), "net": "BUS"])
			if let last { try perform("route_traces", ["points": try MCPJSON([last, via]), "layer": 5, "net": "BUS"]) }
			last = via
		}
		let result = try batched.batch(operations)
		let batchBytes = try JSONEncoder().encode(result).count
		XCTAssertEqual(batched.editor.design, singles.editor.design)
		XCTAssertEqual(batched.editor.design.faults(), [])
		XCTAssertLessThan(batchBytes, bytes / 4)
		let measurement = "MCP routing benchmark: \(operations.count) calls / \(bytes) response bytes; batch: 1 call / \(batchBytes) response bytes"
		let attachment = XCTAttachment(string: measurement)
		attachment.lifetime = .keepAlways
		add(attachment)
		print(measurement)
	}

	func testEmptyRevealSelectionIsAcceptedByTheSchema() throws {
		let tool = try XCTUnwrap(MCPTools.catalog.first { $0.name == "xcopper_reveal_objects" })
		try MCPSchema.validate(["documentId": "DOC", "expectedRevision": 1, "view": "layout", "objects": []], schema: tool.inputSchema)
	}

	func testSchemaErrorsIdentifyTheFailingBatchOperation() throws {
		let tool = try XCTUnwrap(MCPTools.catalog.first { $0.name == "xcopper_apply_edits" })
		XCTAssertThrowsError(try MCPSchema.validate(["documentId": "DOC", "expectedRevision": 1, "operations": [placement(), ["id": "bad", "tool": "save_document", "arguments": [:]]]], schema: tool.inputSchema)) { error in
			XCTAssertEqual((error as? MCPFailure)?.details["operationIndex"], 1)
			XCTAssertEqual((error as? MCPFailure)?.details["operationId"], "bad")
		}
	}
}
