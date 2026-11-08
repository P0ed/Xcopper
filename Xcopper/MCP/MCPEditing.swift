import Foundation
import MCP

@MainActor
extension MCPTools {
	static func edit(_ name: String, _ args: MCPArguments, entry: MCPDocumentEntry, design: inout Design) throws {
		switch name {
		case "configure_design":
			if args.values["sheetSize"] != nil { design.board.sheetSize = try args.size("sheetSize") }
			if args.values["boardSize"] != nil { design.board.size = try args.size("boardSize") }
			if let count = args.values["layers"]?.intValue, let stack = Stack(rawValue: count) {
				guard design.canRestack(stack) else { throw MCPFailure("module_stack", "An imported module needs more copper layers. Increase the stackup or replace its source first.") }
				design.restack(stack)
			}
			if let mask = args.values["solderMask"]?.boolValue { design.board.solderMask = mask }
			if let rules = args.values["rules"]?.objectValue {
				if let value = rules["clearance"]?.intValue { design.board.rules.clearance = value }
				if let value = rules["traceWidth"]?.intValue { design.board.rules.traceWidth = value }
				if let value = rules["minTraceLength"]?.intValue { design.board.rules.minTraceLength = value }
				if let value = rules["viaDrill"]?.intValue { design.board.rules.viaDrill = value }
				if let value = rules["viaPad"]?.intValue { design.board.rules.viaPad = value }
			}
			if let parameters = args.values["parameters"]?.objectValue {
				for (key, value) in parameters {
					guard let index = design.parameters.firstIndex(where: { $0.name == key }) else { throw MCPFailure("unknown_parameter", "No design parameter named \(key). Place a part with value #\(key) first.") }
					design.parameters[index].defaultValue = value.stringValue!
				}
			}
		case "place_part":
			try placePart(args, design: &design)
		case "update_part":
			let object = try entry.object(args.string("object"), in: design)
			guard object.kind == "part", let index = Int(object.key) else { throw MCPFailure("wrong_object", "update_part requires a native part handle.") }
			try updatePart(args, index: index, design: &design)
		case "set_pin_labels":
			let object = try entry.object(args.string("object"), in: design)
			let labels = try args.object("labels").values
			if object.kind == "part" { try setLabels(labels, part: Int(object.key)!, design: &design) }
			else if object.kind == "module", let index = design.modules.firstIndex(where: { $0.id.uuidString == object.key }) { try setModuleLabels(labels, index: index, design: &design) }
			else { throw MCPFailure("wrong_object", "Pin labels require a native part or module handle.") }
		case "add_wires":
			for path in try args.array("paths") {
				let points = try path.arrayValue!.map { try MCPArguments($0) }.map { try Point(x: $0.int("x"), y: $0.int("y")) }
				for (start, end) in zip(points, points.dropFirst()) {
					guard start != end, start.x == end.x || start.y == end.y else { throw MCPFailure("routing_error", "Schematic wires must have nonzero horizontal or vertical segments.") }
					design.board.wires.append(Wire(start: start, end: end))
				}
			}
		case "route_traces":
			let layer = try args.int("layer")
			guard design.board.stack.isSignal(layer) else { throw MCPFailure("invalid_layer", "Route traces on signal layers 0 or \(design.board.stack.bottom). Internal layers are planes.") }
			let points = try args.array("points").map { try MCPArguments($0) }.map { try Point(x: $0.int("x"), y: $0.int("y")) }
			let net = resolveNet(args.values["net"], design: &design)
			for (start, end) in zip(points, points.dropFirst()) {
				let delta = end - start
				guard start != end, delta.x == 0 || delta.y == 0 || abs(delta.x) == abs(delta.y) else { throw MCPFailure("routing_error", "Trace segments must be nonzero and horizontal, vertical or 45 degrees.") }
			}
			do {
				try design.finishRoute(points: points, width: args.values["width"]?.intValue, layer: layer, net: net, grid: args.values["grid"]?.intValue ?? 100)
			} catch let failure as RouteFinishingFailure {
				throw MCPFailure("routing_error", "The route could not be finished: " + failure.reason, details: [
					"at": try MCPJSON(failure.junction.point), "layer": .int(failure.junction.layer),
					"turnDegrees": failure.turn.map { .int($0 * 45) } ?? .null,
					"directions": try MCPJSON(failure.directions), "vertexIndex": points.firstIndex(of: failure.junction.point).map { .int($0) } ?? .null,
					"segmentLengths": .array(failure.lengths.map { .double($0) }), "grid": .int(failure.grid),
					"reason": .string(failure.reason), "attemptedRepair": .string(failure.attemptedRepair)
				])
			}
		case "place_via":
			let at = try args.point("at")
			let net = resolveNet(args.values["net"], design: &design)
			design.board.vias.append(Via(at: at, net: net))
		case "place_hole":
			design.board.holes.append(try Hole(at: args.point("at"), diameter: args.int("diameter")))
		case "update_objects":
			let updates = try args.array("updates").map { try MCPArguments($0) }
			let objects = try updates.map { try entry.object($0.string("object"), in: design) }
			for (update, object) in zip(updates, objects) {
				let index = Int(object.key) ?? -1
				let fields = Set(update.values.keys).subtracting(["object"])
				switch object.kind {
				case "trace":
					guard fields.isSubset(of: ["width", "layer", "net"]) else { throw MCPFailure("wrong_property", "Traces accept width, layer and net.") }
					if update.values["width"] != nil { design.board.traces[index].width = update.values["width"]?.intValue }
					if let layer = update.values["layer"]?.intValue {
						guard design.board.stack.isSignal(layer) else { throw MCPFailure("invalid_layer", "Trace layers must be 0 or \(design.board.stack.bottom).") }
						design.board.traces[index].layer = layer
					}
					if let value = update.values["net"] { let net = resolveNet(value, design: &design); design.board.traces[index].net = net }
				case "via":
					guard fields.isSubset(of: ["net"]) else { throw MCPFailure("wrong_property", "Vias accept net; their diameters use the board rules.") }
					if let value = update.values["net"] { let net = resolveNet(value, design: &design); design.board.vias[index].net = net }
				case "hole":
					guard fields.isSubset(of: ["diameter"]) else { throw MCPFailure("wrong_property", "Holes accept diameter.") }
					if let diameter = update.values["diameter"]?.intValue { design.board.holes[index].diameter = diameter }
				default: throw MCPFailure("wrong_object", "update_objects accepts native traces, vias and holes.")
				}
			}
		case "transform_objects", "delete_objects":
			try transform(name, args, entry: entry, design: &design)
		case "place_module", "update_module", "replace_module_source", "reload_modules":
			try editModule(name, args, entry: entry, design: &design)
		default: throw MCPFailure("unknown_tool", "Unknown design editing tool.")
		}
	}

	private static func placePart(_ args: MCPArguments, design: inout Design) throws {
		let spec = try args.object("spec")
		let at = try args.point("at")
		let schematic = try args.string("view") == "schematic"
		guard ["component", "symbolKind", "footprintKind"].filter({ spec.values[$0] != nil }).count == 1 else { throw MCPFailure("invalid_spec", "Specify exactly one of component, symbolKind or footprintKind.") }
		let component = spec.values["component"]?.stringValue.flatMap(Component.init(rawValue:))
		let pins = spec.values["pins"]?.intValue ?? 8
		var part: Footprint
		if let footprintKind = spec.values["footprintKind"]?.stringValue.flatMap(Footprint.Kind.init(rawValue:)) {
			guard ![.dip, .soic].contains(footprintKind) || pins % 2 == 0 else { throw MCPFailure("invalid_spec", "SOIC and DIP packages require an even pin count.") }
			let footprint = Footprint.Spec(kind: footprintKind, chip: spec.values["chip"]?.stringValue.flatMap(Footprint.Chip.init(rawValue:)) ?? .c1206, device: spec.values["device"]?.stringValue.flatMap(Device.init(rawValue:)), pins: pins, rows: spec.values["rows"]?.intValue ?? 1)
			part = Footprint(spec: footprint, reference: design.nextReference(like: footprint.referencePrefix), at: .zero)
		} else {
			let kind = component?.symbolKind ?? spec.values["symbolKind"]?.stringValue.flatMap(Symbol.Kind.init(rawValue:)) ?? .resistor
			let symbol = Symbol.Spec(kind: kind, pins: pins, component: component)
			part = Footprint(symbol: symbol, reference: design.nextReference(like: symbol.referencePrefix), at: .zero)
		}
		let rotation = args.values["rotation"] == nil ? Rotation.r0 : try args.rotation("rotation")
		let counterpartRotation = args.values["counterpartRotation"] == nil ? Rotation.r0 : try args.rotation("counterpartRotation")
		part.symbol.rotation = schematic ? rotation : counterpartRotation
		part.rotation = schematic ? counterpartRotation : rotation
		let counterpart = args.values["counterpartAt"] == nil ? nil : try args.point("counterpartAt")
		let index = design.place(part, schematicAt: schematic ? at : counterpart, layoutAt: schematic ? counterpart : at)
		try updatePart(args, index: index, design: &design)
		if let labels = args.values["labels"]?.objectValue { try setLabels(labels, part: index, design: &design) }
	}

	private static func updatePart(_ args: MCPArguments, index: Int, design: inout Design) throws {
		if let reference = args.values["reference"]?.stringValue {
			guard reference == design.board.footprints[index].reference || design.referenceIsFree(reference) else { throw MCPFailure("duplicate_reference", "Part and module references must be nonempty and unique.") }
			design.board.footprints[index].reference = reference
		}
		if let value = args.values["value"]?.stringValue { design.board.footprints[index].value = value }
		if let inBOM = args.values["inBOM"]?.boolValue { design.board.footprints[index].inBOM = inBOM }
	}

	private static func label(_ value: MCPJSON) throws -> String? {
		guard let text = value.stringValue?.trimmingWhitespace, !text.isEmpty else { return nil }
		guard !text.hasPrefix("#") || IODesignator(text) != nil else { throw MCPFailure("invalid_label", "Module IO labels use # followed by a positive pin number and a name, such as #1 OUT.") }
		return text
	}

	private static func setLabels(_ labels: [String: MCPJSON], part: Int, design: inout Design) throws {
		for (number, value) in labels {
			guard let pin = design.board.footprints[part].symbol.pins.firstIndex(where: { $0.number == number }) else { throw MCPFailure("unknown_pin", "Part has no pin numbered \(number). Inspect the design's pins.") }
			design.board.footprints[part].symbol.pins[pin].netLabel = try label(value)
		}
	}

	private static func setModuleLabels(_ labels: [String: MCPJSON], index: Int, design: inout Design) throws {
		for (number, value) in labels {
			guard design.modules[index].interface.contains(where: { String($0.number) == number }) else { throw MCPFailure("unknown_pin", "Module has no pin numbered \(number). Inspect its interface.") }
			design.modules[index][netLabel: number] = try label(value)
		}
	}

	private static func resolveNet(_ value: MCPJSON?, design: inout Design) -> Net.ID? {
		guard let name = value?.stringValue else { return nil }
		return design.net(named: name).id
	}

	private static func transform(_ name: String, _ args: MCPArguments, entry: MCPDocumentEntry, design: inout Design) throws {
		let handles = try args.strings("objects")
		let schematic = try args.string("view") == "schematic"
		let action = name == "delete_objects" ? "delete" : try args.string("action")
		if schematic {
			let refs = try entry.schematicRefs(handles, in: design)
			switch action {
			case "delete": design.deleteSchematic(refs)
			case "move":
				guard try design.moveSchematic(refs, by: args.point("delta"), grid: args.values["grid"]?.intValue ?? 2540) != nil else { throw MCPFailure("routing_error", "The schematic move could not preserve its connections. Try another delta or grid.") }
			case "duplicate": _ = try design.duplicateSchematic(refs, by: args.point("delta"))
			case "rotate": for _ in 0 ..< (try args.rotation("rotation").rawValue) { design.rotateSchematic(refs, clockwise: true) }
			case "flip":
				guard !refs.hasModules else { throw MCPFailure("unsupported_transform", "Module instances cannot be flipped.") }
				design.board.mirrorSchematic(refs)
			default: break
			}
		} else {
			let refs = try entry.layoutRefs(handles, in: design)
			switch action {
			case "delete": design.deleteLayout(refs)
			case "move":
				guard try design.moveLayout(refs, by: args.point("delta"), grid: args.values["grid"]?.intValue ?? 100) != nil else { throw MCPFailure("routing_error", "The layout move could not preserve its connections. Try another delta or grid.") }
			case "duplicate": _ = try design.duplicateLayout(refs, by: args.point("delta"))
			case "rotate": for _ in 0 ..< (try args.rotation("rotation").rawValue) { design.rotateLayout(refs, clockwise: true) }
			case "flip":
				guard !refs.hasModules else { throw MCPFailure("unsupported_transform", "Module instances cannot be flipped.") }
				guard refs.allSatisfy({ $0.kind == .trace || $0.kind == .footprint }) else { throw MCPFailure("unsupported_transform", "Layout flipping accepts only parts and traces.") }
				design.board.flip(refs)
			default: break
			}
		}
	}

	private static func editModule(_ name: String, _ args: MCPArguments, entry: MCPDocumentEntry, design: inout Design) throws {
		let id: UUID
		if name == "place_module" {
			let access = try MCPAccess.shared.moduleAccess(for: entry.url)
			defer { access.close() }
			let library = try access.library()
			id = try design.importModule(filename: args.string("source"), documentURL: entry.url!, library: library, read: access.read)
		} else if name == "reload_modules" {
			guard !design.modules.isEmpty else { return }
			let access = try MCPAccess.shared.moduleAccess(for: entry.url)
			defer { access.close() }
			let library = try access.library()
			var resolver = ModuleResolver(folder: entry.url!.deletingLastPathComponent(), library: library, read: access.read)
			resolver.reload(&design, documentURL: entry.url)
			guard design.moduleErrors.isEmpty else { throw MCPFailure("module_error", design.moduleErrors.joined(separator: "\n")) }
			return
		} else {
			let object = try entry.object(args.string("object"), in: design)
			guard object.kind == "module", let parsed = UUID(uuidString: object.key) else { throw MCPFailure("wrong_object", "A module instance handle is required.") }
			id = parsed
		}
		guard let index = design.modules.firstIndex(where: { $0.id == id }) else { throw MCPFailure("invalid_object", "Module instance was not found.") }
		if name == "replace_module_source" {
			let access = try MCPAccess.shared.moduleAccess(for: entry.url)
			defer { access.close() }
			let library = try access.library()
			_ = try design.replaceModuleSource(id, filename: args.string("source"), documentURL: entry.url!, library: library, read: access.read)
			return
		}
		if let reference = args.values["reference"]?.stringValue {
			guard design.referenceIsFree(reference, ignoring: id) else { throw MCPFailure("duplicate_reference", "Module and part references must be nonempty and unique.") }
			design.modules[index].reference = reference
		}
		if let parameters = args.values["parameters"]?.objectValue {
			for (key, value) in parameters {
				guard design.modules[index].parameters.contains(where: { $0.name == key }) else { throw MCPFailure("unknown_parameter", "Module has no parameter named \(key).") }
				design.modules[index].parameterValues[key] = value.stringValue!
			}
		}
		if let labels = args.values["labels"]?.objectValue { try setModuleLabels(labels, index: index, design: &design) }
		if args.values["layoutRotation"] != nil { design.turnModule(id, to: try args.rotation("layoutRotation"), layout: true) }
		if args.values["schematicRotation"] != nil { design.turnModule(id, to: try args.rotation("schematicRotation"), layout: false) }
		if args.values["layoutAt"] != nil {
			let delta = try args.point("layoutAt") - design.modules[index].layoutAt
			guard design.moveLayout([.module(id)], by: delta, grid: 100) != nil else { throw MCPFailure("routing_error", "Module layout move could not preserve connections.") }
		}
		if args.values["schematicAt"] != nil {
			let delta = try args.point("schematicAt") - design.modules[index].schematicAt
			guard design.moveSchematic([.module(id)], by: delta) != nil else { throw MCPFailure("routing_error", "Module schematic move could not preserve connections.") }
		}
	}

	static func validate(_ design: Design) throws {
		let board = design.board
		guard !board.size.isEmpty, !board.sheetSize.isEmpty else { throw MCPFailure("invalid_geometry", "Board and sheet dimensions must be positive.") }
		guard board.rules.isValid, board.rules.clearance >= 0, board.rules.traceWidth > 0 else { throw MCPFailure("invalid_rules", "Rules require positive trace width, nonnegative clearance and minimum length, and 100 < via drill < via pad.") }
		let references = board.footprints.map(\.reference) + design.modules.map(\.reference)
		guard references.allSatisfy({ !$0.trimmingWhitespace.isEmpty }), Set(references).count == references.count else { throw MCPFailure("duplicate_reference", "Part and module references must be nonempty and unique.") }
		guard board.traces.allSatisfy({ board.stack.contains($0.layer) && ($0.width ?? board.rules.traceWidth) > 0 }), board.holes.allSatisfy({ $0.diameter > 0 }) else { throw MCPFailure("invalid_geometry", "Copper layers, widths and hole diameters must be valid.") }
		let count = board.footprints.count + board.traces.count + board.wires.count + board.vias.count + board.holes.count + design.modules.count
		guard count <= 10_000 else { throw MCPFailure("design_limit", "An MCP edit can contain at most 10,000 native objects.") }
		let points = board.footprints.flatMap { [$0.at, $0.symbol.at] } + board.traces.flatMap { [$0.start, $0.end] } + board.wires.flatMap { [$0.start, $0.end] } + board.vias.map(\.at) + board.holes.map(\.at) + design.modules.flatMap { [$0.layoutAt, $0.schematicAt] }
		guard points.allSatisfy({ (-10_000_000 ... 10_000_000).contains($0.x) && (-10_000_000 ... 10_000_000).contains($0.y) }) else { throw MCPFailure("invalid_geometry", "Transformed coordinates must stay within ten metres of the origin.") }
	}
}
