import Foundation
import MCPS

typealias MCPJSON = MCPS.Value

struct MCPArguments {
	var values: [String: MCPJSON]

	init(_ values: [String: MCPJSON]) { self.values = values }
	init(_ value: MCPJSON) throws {
		guard let values = value.objectValue else { throw MCPFailure("invalid_arguments", "Expected a JSON object.") }
		self.values = values
	}

	func string(_ name: String) throws -> String {
		guard let value = values[name]?.stringValue else { throw MCPFailure("invalid_arguments", "\(name) must be a string.") }
		return value
	}
	func int(_ name: String) throws -> Int {
		guard let value = values[name]?.intValue else { throw MCPFailure("invalid_arguments", "\(name) must be an integer.") }
		return value
	}
	func point(_ name: String) throws -> Point {
		let args = try object(name)
		return try Point(x: args.int("x"), y: args.int("y"))
	}
	func size(_ name: String) throws -> Size {
		let args = try object(name)
		return try Size(width: args.int("width"), height: args.int("height"))
	}
	func object(_ name: String) throws -> MCPArguments {
		guard let value = values[name] else { throw MCPFailure("invalid_arguments", "Missing \(name).") }
		return try MCPArguments(value)
	}
	func array(_ name: String) throws -> [MCPJSON] {
		guard let value = values[name]?.arrayValue else { throw MCPFailure("invalid_arguments", "\(name) must be an array.") }
		return value
	}
	func strings(_ name: String) throws -> [String] {
		try array(name).map {
			guard let string = $0.stringValue else { throw MCPFailure("invalid_arguments", "\(name) must contain strings.") }
			return string
		}
	}
	func rotation(_ name: String) throws -> Rotation {
		let degrees = try int(name)
		guard degrees % 90 == 0, let rotation = Rotation(rawValue: degrees / 90) else { throw MCPFailure("invalid_arguments", "\(name) must be 0, 90, 180 or 270 degrees.") }
		return rotation
	}
}

enum MCPSchema {
	static func object(_ properties: [String: MCPJSON], required: [String] = [], additional: MCPJSON = false) -> MCPJSON {
		["type": "object", "properties": .object(properties), "required": .array(required.map { .string($0) }), "additionalProperties": additional]
	}
	static func string(_ description: String) -> MCPJSON { ["type": "string", "description": .string(description), "minLength": 1, "maxLength": 4096] }
	static func integer(_ description: String, min: Int = 0, max: Int = 2_000_000) -> MCPJSON {
		["type": "integer", "description": .string(description), "minimum": .int(min), "maximum": .int(max)]
	}
	static func choice(_ values: [String], _ description: String) -> MCPJSON {
		["type": "string", "description": .string(description), "enum": .array(values.map { .string($0) })]
	}
	static func array(_ items: MCPJSON, min: Int = 1, max: Int = 256) -> MCPJSON {
		["type": "array", "items": items, "minItems": .int(min), "maxItems": .int(max)]
	}
	static func nullable(_ value: MCPJSON) -> MCPJSON { ["anyOf": .array([value, ["type": "null"]])] }
	static let point = object(["x": integer("X coordinate in micrometres.", min: -2_000_000), "y": integer("Y coordinate in micrometres.", min: -2_000_000)], required: ["x", "y"])
	static let size = object(["width": integer("Width in micrometres.", min: 1), "height": integer("Height in micrometres.", min: 1)], required: ["width", "height"])
	static let rotation: MCPJSON = ["type": "integer", "enum": [0, 90, 180, 270], "description": "Clockwise degrees, in quarter turns."]
	static let view = choice(["schematic", "layout"], "The view whose geometry is edited.")
	static let handle = string("Opaque object handle returned by get_design for this document revision.")
	static let net = nullable(string("Net name; creates the named net if needed. Null clears an assignment; omitted copper nets inherit connected nets."))
	static let labels = object([:], additional: nullable(["type": "string", "maxLength": 4096]))
	static let parameters = object([:], additional: ["type": "string", "maxLength": 4096])
	static let rules = object([
		"clearance": integer("Copper clearance in micrometres.", max: 100_000),
		"traceWidth": integer("Default trace width in micrometres.", min: 1, max: 100_000),
		"minTraceLength": integer("Minimum trace segment length in micrometres.", max: 100_000),
		"viaDrill": integer("Via drill diameter in micrometres; above 100 and smaller than viaPad.", min: 101, max: 100_000),
		"viaPad": integer("Via pad diameter in micrometres; greater than viaDrill.", min: 102, max: 100_000)
	])
	static let spec = object([
		"component": choice(Component.allCases.map(\.rawValue), "Manufacturer component from search_library. Takes precedence over generic specifications."),
		"symbolKind": choice(Symbol.Kind.allCases.map(\.rawValue), "Generic symbol. Paired footprint uses the matching default package."),
		"footprintKind": choice(Footprint.Kind.allCases.map(\.rawValue), "Generic footprint; paired symbol uses its device."),
		"chip": choice(Footprint.Chip.allCases.map(\.rawValue), "Chip size; default c1206."),
		"device": choice(Device.genericCases.map(\.rawValue), "Generic device for a footprint."),
		"pins": integer("Generic IC or package pin count; default 8. SOIC and DIP require an even count.", min: 2, max: 128),
		"rows": integer("Header row count, default 1.", min: 1, max: 2)
	])

	static func validate(_ value: MCPJSON, schema: MCPJSON, path: String = "arguments") throws {
		let s = schema.objectValue ?? [:]
		if let choices = s["anyOf"]?.arrayValue {
			guard choices.contains(where: { (try? validate(value, schema: $0, path: path)) != nil }) else { throw MCPFailure("invalid_arguments", "\(path) has an invalid type or value.") }
			return
		}
		if let choices = s["enum"]?.arrayValue, !choices.contains(value) { throw MCPFailure("invalid_arguments", "\(path) is not an allowed value.") }
		func invalid(_ detail: String) -> MCPFailure { MCPFailure("invalid_arguments", "\(path) \(detail).") }
		switch s["type"]?.stringValue {
		case "object":
			guard let object = value.objectValue else { throw invalid("must be an object") }
			let properties = s["properties"]?.objectValue ?? [:]
			for name in s["required"]?.arrayValue?.compactMap(\.stringValue) ?? [] where object[name] == nil { throw invalid("requires \(name)") }
			guard object.count <= 256 else { throw invalid("has too many fields") }
			for (key, value) in object {
				if let field = properties[key] { try validate(value, schema: field, path: path + "." + key) }
				else if s["additionalProperties"] == false { throw invalid("does not accept \(key)") }
				else if let extra = s["additionalProperties"], extra.objectValue != nil { try validate(value, schema: extra, path: path + "." + key) }
			}
		case "array":
			guard let array = value.arrayValue else { throw invalid("must be an array") }
			guard array.count >= (s["minItems"]?.intValue ?? 0), array.count <= (s["maxItems"]?.intValue ?? 256) else { throw invalid("has an invalid number of items") }
			if let item = s["items"] {
				for (index, value) in array.enumerated() {
					do { try validate(value, schema: item, path: path + "[\(index)]") }
					catch var failure as MCPFailure {
						if path == "arguments.operations" {
							failure.details["operationIndex"] = .int(index)
							if let id = value.objectValue?["id"] { failure.details["operationId"] = id }
						}
						throw failure
					}
				}
			}
		case "string":
			guard let string = value.stringValue, string.count >= (s["minLength"]?.intValue ?? 0), string.count <= (s["maxLength"]?.intValue ?? 4096) else { throw invalid("must be a string of the permitted length") }
		case "integer":
			guard let int = value.intValue, int >= (s["minimum"]?.intValue ?? Int.min), int <= (s["maximum"]?.intValue ?? Int.max) else { throw invalid("must be an integer in the permitted range") }
		case "boolean": guard value.boolValue != nil else { throw invalid("must be a boolean") }
		case "null": guard value == .null else { throw invalid("must be null") }
		default: break
		}
	}
}

enum MCPTools {
	private static func tool(_ name: String, _ description: String, _ properties: [String: MCPJSON] = [:], required: [String] = [], document: Bool = false, edit: Bool = false, readOnly: Bool = false) -> MCPS.Tool {
		var fields = properties
		var required = required
		if document || edit { fields["documentId"] = MCPSchema.string("Runtime UUID from list_documents."); required.append("documentId") }
		if edit || ["create_document", "open_document", "save_document"].contains(name) { fields["response"] = MCPSchema.choice(["compact", "full"], "Mutation response detail; existing tools default to full.") }
		if edit { fields["expectedRevision"] = MCPSchema.integer("Revision from the most recent inspection. Reinspect on stale_revision.", min: 1, max: Int.max); required.append("expectedRevision") }
		return MCPS.Tool(name: "xcopper_" + name, description: description, inputSchema: MCPSchema.object(fields, required: required), annotations: .init(readOnlyHint: readOnly, destructiveHint: !readOnly, idempotentHint: readOnly, openWorldHint: false))
	}

	static let catalog: [MCPS.Tool] = [
		tool("list_documents", "List every live Xcopper document, independent of window focus, with runtime IDs, revisions, paths, dirty and busy state.", readOnly: true),
		tool("create_document", "Create and natively save a new design at a workspace-relative .pcb path, then open its window. Existing destinations require overwrite=true.", ["path": MCPSchema.string("Workspace-relative .pcb destination."), "overwrite": ["type": "boolean"]], required: ["path"]),
		tool("open_document", "Open a workspace .pcb file through the native document controller, or return an already open document with its existing access grant.", ["path": MCPSchema.string("Workspace-relative or absolute .pcb path.")], required: ["path"]),
		tool("save_document", "Save using the native document system. Untitled documents require a workspace destination; an existing different destination requires overwrite=true.", ["path": MCPSchema.string("Optional .pcb destination in the workspace."), "overwrite": ["type": "boolean"]], document: true),
		tool("close_document", "Save changes using the native document system, then close the document. Untitled documents require a destination.", ["path": MCPSchema.string("Optional .pcb destination in the workspace."), "overwrite": ["type": "boolean"]], document: true),
		tool("get_design", "Inspect a design, optionally filtering sections, references and nets. Handles belong to this revision; imported internals and pads are read only.", ["sections": MCPSchema.array(MCPSchema.choice(["parts", "wires", "traces", "vias", "holes", "modules", "nets", "parameters"], "Sections to include."), min: 0), "references": MCPSchema.array(MCPSchema.string("Native or qualified component/module reference.")), "nets": MCPSchema.array(MCPSchema.string("Resolved net name."))], document: true, readOnly: true),
		tool("search_library", "Discover manufacturer components and generic symbol/footprint specifications, including default pin and pad geometry. Use the returned spec in place_part.", ["query": ["type": "string", "maxLength": 256]], readOnly: true),
		tool("list_module_sources", "Discover .pcb module sources under the document folder using workspace access; return interfaces, geometry, parameters and load diagnostics.", document: true, readOnly: true),
		tool("check_design", "Return DRC violations, unrouted connections, schematic connectivity diagnostics, module errors and the inspected revision.", document: true, readOnly: true),
		tool("apply_edits", "Apply ordered design edits atomically in one Undo step. Each operation has tool, arguments and optional id. Use $id as an object handle for an earlier placement result. dryRun returns a preview without committing or allocating live handles. Responses default to compact.", ["operations": MCPSchema.array(MCPSchema.object(["tool": MCPSchema.choice(designEdits, "Design editing tool without the xcopper_ prefix."), "arguments": MCPSchema.object([:], additional: true), "id": MCPSchema.string("Unique operation name, also usable as a placement alias.")], required: ["tool", "arguments"])), "name": MCPSchema.string("Undo action name."), "dryRun": ["type": "boolean"]], required: ["operations"], edit: true),
		tool("get_netlist", "Return resolved hierarchical references, component values, pin numbers and nets for external circuit analysis.", document: true, readOnly: true),
		tool("render_design", "Render an inline PNG from the native layout or schematic rendering geometry without changing selection or viewport. Optional proposalId previews planned copper. Defaults to 1024x1024 and fitted board/sheet bounds.", ["view": MCPSchema.view, "proposalId": MCPSchema.handle, "bounds": MCPSchema.object(["origin": MCPSchema.point, "size": MCPSchema.size], required: ["origin", "size"]), "layers": MCPSchema.array(MCPSchema.integer("Visible copper layer.", max: 5), min: 0, max: 6), "width": MCPSchema.integer("Image width in pixels.", min: 64, max: 2048), "height": MCPSchema.integer("Image height in pixels.", min: 64, max: 2048), "ratsnest": ["type": "boolean"], "silkscreen": ["type": "boolean"]], required: ["view"], document: true, readOnly: true),
		tool("plan_connection", "Plan one same-net connection without modifying the document. Supply a connection handle from check_design or from/to pad, trace, via or island handles; to=plane connects to the source net's plane. Existing copper stays fixed. Returns exact copper and a proposal valid for ten minutes at this revision.", ["connection": MCPSchema.handle, "from": MCPSchema.handle, "to": MCPSchema.string("Endpoint handle or plane."), "layers": MCPSchema.array(MCPSchema.integer("Permitted outer signal layer index.", max: 5), max: 2), "width": MCPSchema.integer("Trace width; default board rule.", min: 1, max: 100_000), "clearance": MCPSchema.integer("Clearance, at least the board rule.", max: 100_000), "viaLimit": MCPSchema.integer("Maximum added through vias; default 4.", max: 16), "grid": MCPSchema.integer("Search grid; default 100 micrometres.", min: 1, max: 100_000), "maxNodes": MCPSchema.integer("Search budget; default 200000 states.", min: 1, max: 1_000_000)], edit: true, readOnly: true),
		tool("apply_connection", "Commit the exact copper from a current plan_connection proposal in one Undo step. Defaults to a compact response.", ["proposalId": MCPSchema.handle], required: ["proposalId"], edit: true),
		tool("fit_view", "Fit the board or sheet in the requested native view without changing the design or revision.", ["view": MCPSchema.view], required: ["view"], edit: true),
		tool("configure_design", "Set sheet/board dimensions, 2/4/6-layer stackup, solder mask, rule fields and module parameter defaults. A layer reduction must support imported modules.", ["sheetSize": MCPSchema.size, "boardSize": MCPSchema.size, "layers": ["type": "integer", "enum": [2, 4, 6]], "solderMask": ["type": "boolean"], "rules": MCPSchema.rules, "parameters": MCPSchema.parameters], edit: true),
		tool("place_part", "Place a paired symbol and footprint. at and rotation apply to view; the counterpart is parked unless counterpartAt/counterpartRotation are supplied. Use a component, symbolKind or footprintKind spec.", ["spec": MCPSchema.spec, "view": MCPSchema.view, "at": MCPSchema.point, "rotation": MCPSchema.rotation, "counterpartAt": MCPSchema.point, "counterpartRotation": MCPSchema.rotation, "reference": MCPSchema.string("Unique nonempty reference."), "value": ["type": "string", "maxLength": 4096], "inBOM": ["type": "boolean"], "labels": MCPSchema.labels], required: ["spec", "view", "at"], edit: true),
		tool("update_part", "Update a native paired part's unique reference, value or BOM inclusion. Use transform_objects to change geometry.", ["object": MCPSchema.handle, "reference": MCPSchema.string("Unique nonempty reference."), "value": ["type": "string", "maxLength": 4096], "inBOM": ["type": "boolean"]], required: ["object"], edit: true),
		tool("set_pin_labels", "Set connectivity labels by pin number on a native part or module. Null or empty values clear labels. Matching names connect; '#1 OUT' exposes module IO pin 1.", ["object": MCPSchema.handle, "labels": MCPSchema.labels], required: ["object", "labels"], edit: true),
		tool("add_wires", "Draw schematic wire polylines. Each segment must be nonzero and orthogonal. The entire request commits in one Undo step.", ["paths": MCPSchema.array(MCPSchema.array(MCPSchema.point, min: 2))], required: ["paths"], edit: true),
		tool("route_traces", "Route a copper polyline with nonzero horizontal, vertical or 45-degree segments on a signal layer. Uses existing route finishing and net inheritance; returns routing_error if repair fails.", ["points": MCPSchema.array(MCPSchema.point, min: 2), "layer": MCPSchema.integer("Zero-based signal layer index.", max: 5), "width": MCPSchema.nullable(MCPSchema.integer("Trace width in micrometres; null uses board rules.", min: 1, max: 100_000)), "net": MCPSchema.net, "grid": MCPSchema.integer("Routing repair grid in micrometres; default 100.", min: 1, max: 100_000)], required: ["points", "layer"], edit: true),
		tool("place_via", "Place a through via using board rule pad and drill diameters; inherit a connected net when omitted.", ["at": MCPSchema.point, "net": MCPSchema.net], required: ["at"], edit: true),
		tool("place_hole", "Place a non-plated hole with an explicit diameter in micrometres.", ["at": MCPSchema.point, "diameter": MCPSchema.integer("Hole diameter in micrometres.", min: 1, max: 100_000)], required: ["at", "diameter"], edit: true),
		tool("update_objects", "Atomically edit native trace width/layer/net, via net or hole diameter. Pad and imported module geometry cannot be edited.", ["updates": MCPSchema.array(MCPSchema.object(["object": MCPSchema.handle, "width": MCPSchema.nullable(MCPSchema.integer("Trace width; null uses board rules.", min: 1, max: 100_000)), "layer": MCPSchema.integer("Signal layer index.", max: 5), "net": MCPSchema.net, "diameter": MCPSchema.integer("Hole diameter in micrometres.", min: 1, max: 100_000)], required: ["object"]))], required: ["updates"], edit: true),
		tool("transform_objects", "Move with connection preservation, rotate about selection bounds, flip, or duplicate in the explicit view. move/duplicate require delta; rotate requires rotation. Module flipping is unsupported. grid controls movement repair.", ["objects": MCPSchema.array(MCPSchema.handle), "view": MCPSchema.view, "action": MCPSchema.choice(["move", "rotate", "flip", "duplicate"], "Transformation to apply."), "delta": MCPSchema.point, "rotation": MCPSchema.rotation, "grid": MCPSchema.integer("Movement repair grid, default 100 layout / 2540 schematic.", min: 1, max: 100_000)], required: ["objects", "view", "action"], edit: true),
		tool("delete_objects", "Delete selected wires, copper, holes, paired parts or whole module instances in the explicit view. Deleting a part removes its symbol and footprint together.", ["objects": MCPSchema.array(MCPSchema.handle), "view": MCPSchema.view], required: ["objects", "view"], edit: true),
		tool("place_module", "Import a module source by its discovered name. Validates interfaces, dependencies and stackup. Optional positions, rotations, reference, pin labels and parameter overrides apply to the instance.", moduleFields.merging(["source": MCPSchema.string("Module source name from list_module_sources.")]) { _, new in new }, required: ["source"], edit: true),
		tool("update_module", "Edit module positions, rotations, reference, pin labels and parameter overrides. Movement preserves parent connections. Imported internals remain read only.", moduleFields.merging(["object": MCPSchema.handle]) { _, new in new }, required: ["object"], edit: true),
		tool("replace_module_source", "Replace a module source after validating it. Retains parent wire coordinates and returns interface-change notices.", ["object": MCPSchema.handle, "source": MCPSchema.string("Replacement source name from list_module_sources.")], required: ["object", "source"], edit: true),
		tool("reload_modules", "Reload and validate module sources with workspace access. Any failure leaves the design unchanged.", edit: true),
		tool("undo", "Undo one native document history step. Human changes also advance the revision.", edit: true),
		tool("redo", "Redo one native document history step. Human changes also advance the revision.", edit: true),
		tool("reveal_objects", "Select objects and reveal them in the requested app view. Requires current handles and revision; does not change the design.", ["objects": MCPSchema.array(MCPSchema.handle, min: 0), "view": MCPSchema.view], required: ["objects", "view"], edit: true),
		tool("export_fabrication", "Export the existing Gerber, Excellon, BOM and placement set into a workspace folder. Unresolved modules always block export. DRC findings require allowViolations=true; an existing destination requires overwrite=true.", ["path": MCPSchema.string("Destination folder inside the workspace."), "overwrite": ["type": "boolean"], "allowViolations": ["type": "boolean"]], required: ["path"], document: true)
	]

	private static let moduleFields: [String: MCPJSON] = [
		"reference": MCPSchema.string("Unique module reference."), "schematicAt": MCPSchema.point, "layoutAt": MCPSchema.point,
		"schematicRotation": MCPSchema.rotation, "layoutRotation": MCPSchema.rotation,
		"labels": MCPSchema.labels, "parameters": MCPSchema.parameters
	]

	@MainActor
	static func call(_ params: CallTool.Parameters, serverID: UUID, permit: SessionPermit) async -> CallTool.Result {
		do {
			guard MCPAccess.shared.isRunning, MCPAccess.shared.serverID == serverID else { throw MCPFailure("server_stopped", "The MCP server was stopped. Reconnect after starting it again.") }
			guard permit.isValid else { throw MCPFailure("session_expired", "This MCP session ended. Initialize a new session before making tool calls.") }
			guard let tool = catalog.first(where: { $0.name == params.name }) else { throw MCPFailure("unknown_tool", "Unknown Xcopper tool.") }
			let args = MCPArguments(params.arguments ?? [:])
			try MCPSchema.validate(.object(args.values), schema: tool.inputSchema)
			try Task.checkCancellation()
			let value = try await execute(String(params.name.dropFirst("xcopper_".count)), args)
			return result(value)
		} catch {
			if let failure = error as? MCPExportFailure { return result(failure.result, error: true) }
			let native = error as NSError
			let denied = native.domain == NSCocoaErrorDomain && [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(native.code)
			let code = (error as? MCPFailure)?.code ?? (denied ? "access_required" : error is CancellationError ? "cancelled" : "operation_failed")
			let message = denied ? "File access was denied. Select a containing workspace in AI Access settings, or reopen the document through File → Open, then retry. " + error.localizedDescription : error.localizedDescription
			var body = (error as? MCPFailure)?.details ?? [:]
			body["code"] = .string(code)
			body["message"] = .string(message)
			if let id = params.arguments?["documentId"]?.stringValue,
				let entry = MCPDocuments.shared.documents.first(where: { $0.id.uuidString == id }) {
				entry.refresh()
				body["documentId"] = .string(id)
				body["revision"] = .int(entry.revision)
			}
			return result(["error": .object(body)], error: true)
		}
	}

	static func result(_ supplied: MCPJSON, error: Bool = false) -> CallTool.Result {
		var value = supplied
		var image: MCPS.Tool.Content?
		if var fields = supplied.objectValue, let data = fields.removeValue(forKey: "imageData")?.stringValue {
			value = .object(fields)
			image = .image(data: data, mimeType: "image/png", annotations: nil, _meta: nil)
		}
		let text = (try? JSONEncoder().encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
		return .init(content: [.text(text: text, annotations: nil, _meta: nil)] + (image.map { [$0] } ?? []), structuredContent: Optional.some(value), isError: error)
	}
}
