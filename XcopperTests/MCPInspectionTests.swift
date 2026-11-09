import AppKit
import MCPS
import XCTest
@testable import Xcopper

@MainActor
final class MCPInspectionTests: XCTestCase {
	func testDiagnosticsExposePadIdentitiesConnectionsAndMeasuredClearance() throws {
		var design = ConnectionFixtures.design()
		design.board.footprints.append(ConnectionFixtures.part("J3", at: Point(x: 5000, y: 6000), net: 0))
		design.board.rules.clearance = 300
		let fixture = MCPHarness(design)
		let diagnostics = try fixture.entry.diagnostics().objectValue!
		XCTAssertFalse(diagnostics["connections"]!.arrayValue!.isEmpty)
		let terminals = diagnostics["islands"]!.arrayValue!.flatMap { $0.objectValue!["terminals"]!.arrayValue! }
		XCTAssertTrue(terminals.contains { $0.objectValue?["reference"] == "J1" && $0.objectValue?["pin"] == "1" })
		let clearance = try XCTUnwrap(diagnostics["violations"]?.arrayValue?.first { $0.objectValue?["kind"] == "clearance" }?.objectValue)
		XCTAssertEqual(clearance["required"], .double(300))
		XCTAssertEqual(clearance["measured"], .double(200))
		XCTAssertTrue(clearance["objects"]!.arrayValue!.allSatisfy { $0.stringValue!.contains(":pad:") })
	}

	func testNetlistResolvesModuleReferencesParametersAndNets() throws {
		let root = URL(fileURLWithPath: "/tmp/xcopper-mcp-netlist")
		var source = Design()
		source.place(Symbol.Spec(kind: .resistor), at: Point(x: 10000, y: 10000))
		source.board.footprints[0].value = "#R"
		source.board.footprints[0].symbol.pins[0].netLabel = "#1 IN"
		source.board.footprints[0].symbol.pins[1].netLabel = "GND"
		_ = source.updateBoardFromSchematic()
		let data = try JSONEncoder().encode(source)
		var design = Design()
		let id = try design.importModule(filename: "Buffer.pcb", documentURL: root.appendingPathComponent("Parent.pcb"), library: ModuleLibrary(sources: [root.appendingPathComponent("Buffer.pcb")]), read: { _ in data })
		design.modules[0].parameterValues["R"] = "22k"
		design.modules[0][netLabel: "1"] = "SIGNAL"
		_ = design.updateBoardFromSchematic()
		let fixture = MCPHarness(design)
		let result = try fixture.entry.netlist().objectValue!
		let part = try XCTUnwrap(result["parts"]?.arrayValue?.first?.objectValue)
		XCTAssertEqual(part["reference"], "M1.R1")
		XCTAssertEqual(part["value"], "22k")
		XCTAssertEqual(part["pins"]?.arrayValue?.first?.objectValue?["net"]?.objectValue?["name"], "SIGNAL")
		XCTAssertEqual(design.modules[0].id, id)
	}

	func testCompactResponsesTrackImportedPartsWhenNativeIndicesShift() throws {
		let root = URL(fileURLWithPath: "/tmp/xcopper-mcp-imported-indices")
		var source = Design()
		source.place(Symbol.Spec(kind: .resistor), at: Point(x: 10000, y: 10000))
		source.board.footprints[0].symbol.pins[0].netLabel = "#1 IN"
		let data = try JSONEncoder().encode(source)
		var design = Design()
		_ = try design.importModule(filename: "Buffer.pcb", documentURL: root.appendingPathComponent("Parent.pcb"), library: ModuleLibrary(sources: [root.appendingPathComponent("Buffer.pcb")]), read: { _ in data })
		let fixture = MCPHarness(design)
		let result = try fixture.batch([["tool": "place_part", "arguments": ["spec": ["symbolKind": "resistor"], "view": "layout", "at": ["x": 10000, "y": 10000], "reference": "R1"]]])
		let changes = try XCTUnwrap(result.objectValue?["changes"]?.objectValue)
		XCTAssertEqual(changes["created"]?.arrayValue?.count, 1)
		XCTAssertEqual(changes["created"]?.arrayValue?.first?.objectValue?["reference"], "R1")
		XCTAssertEqual(changes["deleted"]?.arrayValue, [])
		XCTAssertEqual(changes["updated"]?.arrayValue, [])
	}

	func testNativePreviewsReturnInlinePNGWithoutChangingEditorState() throws {
		let fixture = MCPHarness(ConnectionFixtures.design())
		fixture.editor.layout.selection = [.footprint(0)]
		let layout = fixture.editor.layout, schematic = fixture.editor.schematic, original = fixture.editor.design
		let top = try MCPTools.renderDesign(MCPArguments(["view": "layout", "layers": [0], "width": 256, "height": 192]), entry: fixture.entry)
		let bottom = try MCPTools.renderDesign(MCPArguments(["view": "layout", "layers": [1], "width": 256, "height": 192]), entry: fixture.entry)
		let data = try XCTUnwrap(Data(base64Encoded: top.objectValue!["imageData"]!.stringValue!))
		let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
		XCTAssertEqual(bitmap.pixelsWide, 256)
		XCTAssertEqual(bitmap.pixelsHigh, 192)
		XCTAssertNotEqual(top.objectValue?["imageData"], bottom.objectValue?["imageData"])
		let response = MCPTools.result(top)
		XCTAssertEqual(response.content.count, 2)
		XCTAssertNil(response.structuredContent?.objectValue?["imageData"])
		let sheet = try MCPTools.renderDesign(MCPArguments(["view": "schematic", "width": 256, "height": 192]), entry: fixture.entry)
		XCTAssertNotNil(sheet.objectValue?["imageData"])
		XCTAssertEqual(fixture.editor.design, original)
		XCTAssertEqual(fixture.editor.layout, layout)
		XCTAssertEqual(fixture.editor.schematic, schematic)
		XCTAssertEqual(fixture.entry.revision, 1)
		XCTAssertFalse(fixture.editor.undo.canUndo)
	}

	func testPolylineReversalProducesIdenticalFinishedCopper() throws {
		var forward = Design(), reverse = Design()
		let points = [Point(x: 10000, y: 10000), Point(x: 20000, y: 10000), Point(x: 20000, y: 20000), Point(x: 30000, y: 20000)]
		try forward.finishRoute(points: points, width: 200, layer: 0, net: 0, grid: 100)
		try reverse.finishRoute(points: points.reversed(), width: 200, layer: 0, net: 0, grid: 100)
		XCTAssertEqual(forward, reverse)
	}

	func testFailedFinishingIncludesTheCornerAndRepairMeasurements() throws {
		let fixture = MCPHarness()
		let args = fixture.args(["points": [["x": 10000, "y": 10000], ["x": 10100, "y": 10000], ["x": 10100, "y": 20000]], "layer": 0, "grid": 100])
		XCTAssertThrowsError(try MCPTools.performEdits("route_traces", args, entry: fixture.entry)) { error in
			let failure = error as? MCPFailure
			XCTAssertEqual(failure?.code, "routing_error")
			XCTAssertEqual(failure?.details["turnDegrees"], 90)
			XCTAssertEqual(failure?.details["segmentLengths"]?.arrayValue?.count, 2)
			XCTAssertEqual(failure?.details["attemptedRepair"], "chamfer")
		}
		XCTAssertTrue(fixture.editor.design.board.traces.isEmpty)
	}
}
