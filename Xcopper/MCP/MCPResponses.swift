import Foundation
import MCP

@MainActor
extension MCPTools {
	static func documentResponse(_ entry: MCPDocumentEntry, _ args: MCPArguments) throws -> MCPJSON {
		try args.values["response"] == "compact" ? entry.summary() : entry.inspection()
	}

	static func performEdits(_ name: String, _ args: MCPArguments, entry: MCPDocumentEntry) throws -> MCPJSON {
		try entry.requireIdle()
		try entry.requireRevision(args)
		let before = try entry.inspection()
		let revision = entry.revision
		let batch = name == "apply_edits"
		let operations: [MCPJSON]
		if batch { operations = try args.array("operations") }
		else {
			let fields = args.values.filter { !["documentId", "expectedRevision", "response"].contains($0.key) }
			operations = [["tool": .string(name), "arguments": .object(fields)]]
		}
		let prepared = try prepareEdits(operations, entry: entry)
		if batch, args.values["dryRun"] == true {
			let preview = try entry.inspection(design: prepared.design)
			return ["documentId": .string(entry.id.uuidString), "revision": .int(revision), "dryRun": true,
				"preview": withoutHandles(preview, document: entry.id.uuidString), "diagnostics": withoutHandles(try entry.diagnostics(design: prepared.design), document: entry.id.uuidString)]
		}
		try Task.checkCancellation()
		try entry.commit(prepared.design, name: batch ? args.values["name"]?.stringValue ?? "AI: batch edit" : "AI: " + name.replacingOccurrences(of: "_", with: " "))
		var result = try mutationResponse(entry, before: before, objects: prepared.objects, compact: args.values["response"] == "compact" || (batch && args.values["response"] == nil)).objectValue!
		if batch { result["results"] = .object(prepared.aliases.mapValues { .string(entry.handle($0.kind, $0.key)) }) }
		return .object(result)
	}

	static func withoutHandles(_ value: MCPJSON, document: String) -> MCPJSON {
		if let fields = value.objectValue {
			return .object(fields.filter { !["object", "objects", "owners"].contains($0.key) }.mapValues { withoutHandles($0, document: document) })
		}
		if let values = value.arrayValue { return .array(values.map { withoutHandles($0, document: document) }) }
		if let string = value.stringValue, string.hasPrefix(document + ":") { return .null }
		return value
	}

	static func mutationResponse(_ entry: MCPDocumentEntry, before: MCPJSON, objects suppliedObjects: [String: MCPObjectAddress]?, compact: Bool) throws -> MCPJSON {
		let after = try entry.inspection()
		guard compact else { return after }
		let previous = before.objectValue!
		let current = after.objectValue!
		let inferred = matchingObjects(before: before, after: after)
		var objects = suppliedObjects ?? inferred
		for section in ["parts", "traces", "vias", "holes"] {
			for value in previous[section]?.arrayValue ?? [] where value.objectValue?["readOnly"] == true {
				if let handle = value.objectValue?["object"]?.stringValue { objects[handle] = inferred[handle] }
			}
		}
		var created: [MCPJSON] = [], updated: [MCPJSON] = [], deleted: [MCPJSON] = []
		func remap(_ value: MCPJSON) -> MCPJSON {
			if let array = value.arrayValue { return .array(array.map(remap)) }
			if let fields = value.objectValue { return .object(fields.mapValues(remap)) }
			guard let string = value.stringValue, string.hasPrefix(entry.id.uuidString + ":") else { return value }
			if let address = objects[string] { return .string(entry.handle(address.kind, address.key)) }
			let components = string.split(separator: ":").map(String.init)
			guard components.count == 4 else { return value }
			if components[2] == "pad" {
				let indices = components[3].split(separator: "/").map(String.init)
				if indices.count == 2, let parent = objects[components[0] + ":" + components[1] + ":part:" + indices[0]] {
					return .string(entry.handle("pad", parent.key + "/" + indices[1]))
				}
			}
			return .string(entry.handle(components[2], components[3]))
		}
		for section in ["parts", "wires", "traces", "vias", "holes", "modules"] {
			let old = previous[section]?.arrayValue ?? []
			let new = current[section]?.arrayValue ?? []
			var matched: Set<String> = []
			for object in old {
				let handle = object.objectValue!["object"]!.stringValue!
				let moved = remap(object)
				let target = moved.objectValue!["object"]!.stringValue!
				if let next = new.first(where: { $0.objectValue?["object"]?.stringValue == target }), objects[handle] != nil {
					matched.insert(target)
					if moved != next { updated.append(next) }
				} else { deleted.append(.string(handle)) }
			}
			created.append(contentsOf: new.filter { !matched.contains($0.objectValue!["object"]!.stringValue!) })
		}
		var result = entry.summary().objectValue!
		result["previousRevision"] = previous["revision"]
		result["changes"] = ["created": .array(created), "updated": .array(updated), "deleted": .array(deleted)]
		for key in ["boardSize", "sheetSize", "layers", "layerRoles", "solderMask", "rules", "nets", "parameters"] where previous[key] != current[key] { result[key] = current[key] }
		for key in ["moduleErrors", "notices", "schematicDiagnostics"] { result[key] = current[key] }
		result["handlesExpireOnRevisionChange"] = true
		return .object(result)
	}

	private static func matchingObjects(before: MCPJSON, after: MCPJSON) -> [String: MCPObjectAddress] {
		func content(_ value: MCPJSON) -> MCPJSON {
			if let fields = value.objectValue { return .object(fields.filter { $0.key != "object" }.mapValues(content)) }
			if let array = value.arrayValue { return .array(array.map(content)) }
			if let string = value.stringValue, string.split(separator: ":").count == 4 {
				let parts = string.split(separator: ":")
				return .string(parts.suffix(2).joined(separator: ":"))
			}
			return value
		}
		var result: [String: MCPObjectAddress] = [:]
		for section in ["parts", "wires", "traces", "vias", "holes", "modules"] {
			let old = before.objectValue?[section]?.arrayValue ?? []
			let new = after.objectValue?[section]?.arrayValue ?? []
			let groups = Dictionary(grouping: new, by: content)
			let oldGroups = Dictionary(grouping: old, by: content)
			for value in old {
				let key = content(value)
				let matches: [MCPJSON]
				if ["parts", "modules"].contains(section), let reference = value.objectValue?["reference"] {
					matches = new.filter { $0.objectValue?["reference"] == reference && $0.objectValue?["readOnly"] == value.objectValue?["readOnly"] }
				} else { matches = oldGroups[key]?.count == 1 ? groups[key] ?? [] : [] }
				guard matches.count == 1,
					let oldHandle = value.objectValue?["object"]?.stringValue,
					let newHandle = matches[0].objectValue?["object"]?.stringValue else { continue }
				let parts = newHandle.split(separator: ":").map(String.init)
				result[oldHandle] = MCPObjectAddress(kind: parts[2], key: parts[3])
			}
		}
		return result
	}

	nonisolated static func filterInspection(_ inspection: MCPJSON, _ args: MCPArguments) -> MCPJSON {
		var result = inspection.objectValue!
		let sections = args.values["sections"]?.arrayValue?.compactMap(\.stringValue)
		let references = args.values["references"]?.arrayValue?.compactMap(\.stringValue)
		let nets = args.values["nets"]?.arrayValue?.compactMap(\.stringValue)
		func hasNet(_ value: MCPJSON) -> Bool {
			if let fields = value.objectValue {
				if let net = fields["net"]?.objectValue?["name"]?.stringValue, nets?.contains(net) == true { return true }
				return fields.values.contains(where: hasNet)
			}
			return value.arrayValue?.contains(where: hasNet) ?? false
		}
		for section in ["parts", "wires", "traces", "vias", "holes", "modules", "nets", "parameters"] {
			if let sections, !sections.contains(section) { result[section] = nil; continue }
			guard let values = result[section]?.arrayValue else { continue }
			result[section] = .array(values.filter { value in
				if section == "nets" { return nets == nil || nets!.contains(value.objectValue?["name"]?.stringValue ?? "") }
				if let references, ["parts", "modules"].contains(section), !references.contains(value.objectValue?["reference"]?.stringValue ?? "") { return false }
				return nets == nil || hasNet(value)
			})
		}
		return .object(result)
	}
}
