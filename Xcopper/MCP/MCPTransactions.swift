import Foundation
import MCP

struct MCPObjectAddress: Hashable {
	var kind: String
	var key: String
}

struct MCPPreparedEdits {
	var design: Design
	var objects: [String: MCPObjectAddress]
	var aliases: [String: MCPObjectAddress]
}

@MainActor
extension MCPTools {
	nonisolated static let designEdits = [
		"configure_design", "place_part", "update_part", "set_pin_labels", "add_wires", "route_traces",
		"place_via", "place_hole", "update_objects", "transform_objects", "delete_objects",
		"place_module", "update_module", "replace_module_source", "reload_modules"
	]

	static func prepareEdits(_ operations: [MCPJSON], entry: MCPDocumentEntry) throws -> MCPPreparedEdits {
		var candidate = entry.design
		var objects = nativeAddresses(candidate, entry: entry)
		var aliases: [String: MCPObjectAddress] = [:]
		var names: Set<String> = []
		for (index, operation) in operations.enumerated() {
			var operationName: String?
			do {
				try Task.checkCancellation()
				let operation = try MCPArguments(operation)
				operationName = operation.values["id"]?.stringValue
				if let operationName, !names.insert(operationName).inserted { throw MCPFailure("duplicate_operation", "Operation IDs must be unique within a batch.") }
				let name = try operation.string("tool")
				guard designEdits.contains(name), let tool = catalog.first(where: { $0.name == "xcopper_" + name }) else { throw MCPFailure("invalid_operation", "Batches accept design editing tools only.") }
				let supplied = try operation.object("arguments")
				guard supplied.values["documentId"] == nil, supplied.values["expectedRevision"] == nil, supplied.values["response"] == nil else { throw MCPFailure("invalid_arguments", "Document, revision and response options belong to the batch.") }
				func resolve(_ value: MCPJSON) throws -> MCPJSON {
					let text = try MCPArguments(["object": value]).string("object")
					let address: MCPObjectAddress
					if text.hasPrefix("$") {
						guard let found = aliases[String(text.dropFirst())] else { throw MCPFailure("invalid_alias", "The alias is unknown, removed or ambiguous: \(text).") }
						address = found
					} else {
						_ = try entry.object(text, in: entry.design)
						guard let found = objects[text] else { throw MCPFailure("invalid_object", "An earlier operation removed or made this target ambiguous.") }
						address = found
					}
					return .string(entry.handle(address.kind, address.key))
				}
				var values = supplied.values
				if let value = values["object"] { values["object"] = try resolve(value) }
				if let valuesToResolve = values["objects"]?.arrayValue { values["objects"] = .array(try valuesToResolve.map(resolve)) }
				if let updates = values["updates"]?.arrayValue {
					values["updates"] = .array(try updates.map { update in
						var fields = try MCPArguments(update).values
						if let object = fields["object"] { fields["object"] = try resolve(object) }
						return .object(fields)
					})
				}
				values["documentId"] = .string(entry.id.uuidString)
				values["expectedRevision"] = .int(entry.revision)
				try MCPSchema.validate(.object(values), schema: tool.inputSchema)
				let args = MCPArguments(values)
				let previous = candidate
				try edit(name, args, entry: entry, design: &candidate)
				if candidate.needsBoardSync(from: previous) { _ = candidate.updateBoardFromSchematic() }
				candidate.inheritConnectedNets()
				try validate(candidate)
				let remapping = try addressRemapping(name, args, before: previous, after: candidate, entry: entry)
				objects = objects.compactMapValues { remapping[$0] }
				aliases = aliases.compactMapValues { remapping[$0] }
				if let operationName, let created = placementResult(name, before: previous, after: candidate) { aliases[operationName] = created }
			} catch {
				var failure = error as? MCPFailure ?? MCPFailure(error is CancellationError ? "cancelled" : "operation_failed", error.localizedDescription)
				failure.details["operationIndex"] = .int(index)
				if let operationName { failure.details["operationId"] = .string(operationName) }
				throw failure
			}
		}
		return MCPPreparedEdits(design: candidate, objects: objects, aliases: aliases)
	}

	static func nativeAddresses(_ design: Design, entry: MCPDocumentEntry) -> [String: MCPObjectAddress] {
		var result: [String: MCPObjectAddress] = [:]
		for (kind, count) in [("part", design.board.footprints.count), ("trace", design.board.traces.count), ("via", design.board.vias.count), ("hole", design.board.holes.count), ("wire", design.board.wires.count)] {
			for index in 0 ..< count { result[entry.handle(kind, String(index))] = MCPObjectAddress(kind: kind, key: String(index)) }
		}
		for module in design.modules { result[entry.handle("module", module.id.uuidString)] = MCPObjectAddress(kind: "module", key: module.id.uuidString) }
		return result
	}

	private static func placementResult(_ name: String, before: Design, after: Design) -> MCPObjectAddress? {
		switch name {
		case "place_part": return .init(kind: "part", key: String(before.board.footprints.count))
		case "place_via": return .init(kind: "via", key: String(before.board.vias.count))
		case "place_hole": return .init(kind: "hole", key: String(before.board.holes.count))
		case "place_module": return after.modules.first(where: { module in !before.modules.contains { $0.id == module.id } }).map { .init(kind: "module", key: $0.id.uuidString) }
		default: return nil
		}
	}

	private static func addressRemapping(_ name: String, _ args: MCPArguments, before: Design, after: Design, entry: MCPDocumentEntry) throws -> [MCPObjectAddress: MCPObjectAddress] {
		var deleted: [String: Set<Int>] = [:]
		if name == "delete_objects" {
			for handle in try args.strings("objects") {
				let object = try entry.object(handle, in: before)
				if let index = Int(object.key) { deleted[object.kind, default: []].insert(index) }
			}
		}
		var result: [MCPObjectAddress: MCPObjectAddress] = [:]
		func indices(_ kind: String, _ count: Int, _ newCount: Int) {
			let removed = deleted[kind] ?? []
			for index in 0 ..< count where !removed.contains(index) {
				let next = index - removed.count { $0 < index }
				if next < newCount { result[.init(kind: kind, key: String(index))] = .init(kind: kind, key: String(next)) }
			}
		}
		indices("part", before.board.footprints.count, after.board.footprints.count)
		indices("via", before.board.vias.count, after.board.vias.count)
		indices("hole", before.board.holes.count, after.board.holes.count)
		let repairs = name == "route_traces" || name == "configure_design" || (name == "update_module" && (args.values["layoutAt"] != nil || args.values["schematicAt"] != nil))
			|| (name == "transform_objects" && args.values["action"] == "move")
		func matching<T: Hashable>(_ kind: String, _ old: [T], _ new: [T]) {
			if old.elementsEqual(new.prefix(old.count)) { indices(kind, old.count, new.count); return }
			let oldGroups = Dictionary(grouping: old.indices, by: { old[$0] })
			let newGroups = Dictionary(grouping: new.indices, by: { new[$0] })
			for (value, indices) in oldGroups where indices.count == 1 {
				guard let next = newGroups[value], next.count == 1 else { continue }
				result[.init(kind: kind, key: String(indices[0]))] = .init(kind: kind, key: String(next[0]))
			}
		}
		if repairs {
			matching("trace", before.board.traces, after.board.traces)
			matching("wire", before.board.wires, after.board.wires)
		} else {
			indices("trace", before.board.traces.count, after.board.traces.count)
			indices("wire", before.board.wires.count, after.board.wires.count)
		}
		for module in before.modules where after.modules.contains(where: { $0.id == module.id }) {
			let address = MCPObjectAddress(kind: "module", key: module.id.uuidString)
			result[address] = address
		}
		return result
	}
}
