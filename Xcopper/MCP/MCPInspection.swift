import Foundation
import MCPS

@MainActor
extension MCPDocumentEntry {
	func inspection(design inspectedDesign: Design? = nil, revision inspectedRevision: Int? = nil) throws -> MCPJSON {
		refresh()
		let design = inspectedDesign ?? design
		let revision = inspectedRevision ?? revision
		func handle(_ kind: String, _ key: String) -> String { "\(id.uuidString):\(revision):\(kind):\(key)" }
		func handle(_ ref: Ref) -> String {
			switch ref {
			case let .footprint(i): handle("part", String(i))
			case let .pad(i, p): handle("pad", "\(i)/\(p)")
			case let .trace(i): handle("trace", String(i))
			case let .via(i): handle("via", String(i))
			case let .hole(i): handle("hole", String(i))
			case let .module(id): handle("module", id.uuidString)
			}
		}
		let projection = design.moduleProjection(syncNative: true)
		let board = projection.design.board
		func encoded<T: Codable>(_ value: T) throws -> MCPJSON { try MCPJSON(value) }
		func net(_ id: Int?) -> MCPJSON {
			guard let id else { return .null }
			return ["id": .int(id), "name": projection.design.nets.first { $0.id == id }.map { .string($0.name) } ?? .null]
		}
		func owner(_ ref: Ref) -> MCPJSON { projection.owners[ref].map { .string(handle(.module($0))) } ?? .null }
		var parts: [MCPJSON] = []
		for (index, footprint) in board.footprints.enumerated() {
			let imported = projection.owners[.footprint(index)] != nil
			let pins = try footprint.symbol.placedPins.map { pin -> MCPJSON in
				let assignment = projection.schematicNets[pin.at] ?? footprint.pads.first { $0.name == pin.number }?.net
				return ["number": .string(pin.number), "name": .string(pin.name), "at": try encoded(pin.at), "direction": .int(pin.direction.degrees), "label": pin.netLabel.map { .string($0) } ?? .null, "net": net(assignment)]
			}
			let pads = try footprint.placedPads.enumerated().map { padIndex, pad -> MCPJSON in
				["object": .string(handle(.pad(index, padIndex))), "number": .string(pad.name), "at": try encoded(pad.at), "size": try encoded(pad.size), "shape": .string(pad.shape == .rect ? "rect" : "oval"), "drill": .int(pad.drill), "layer": .int(footprint.layer(of: pad, in: board.stack)), "through": .bool(pad.isThrough), "net": net(pad.net), "readOnly": true]
			}
			parts.append([
				"object": .string(handle(.footprint(index))), "reference": .string(footprint.reference), "value": .string(footprint.value),
				"component": footprint.component.map { .string($0.rawValue) } ?? .null, "package": .string(footprint.package.name), "inBOM": .bool(footprint.inBOM),
				"readOnly": .bool(imported), "module": owner(.footprint(index)),
				"layout": ["at": try encoded(footprint.at), "rotation": .int(footprint.rotation.degrees), "flipped": .bool(footprint.flipped), "bounds": try encoded(footprint.placedExtent), "pads": .array(pads)],
				"schematic": imported ? .null : ["at": try encoded(footprint.symbol.at), "rotation": .int(footprint.symbol.rotation.degrees), "mirrored": .bool(footprint.symbol.mirrored), "bounds": try encoded(footprint.symbol.placedExtent), "pins": .array(pins)]
			])
		}
		let wires = try design.board.wires.enumerated().map { i, wire -> MCPJSON in
			["object": .string(handle("wire", String(i))), "start": try encoded(wire.start), "end": try encoded(wire.end), "net": net(projection.schematicNets[wire.start])]
		}
		let traces = try board.traces.enumerated().map { i, trace -> MCPJSON in
			["object": .string(handle(.trace(i))), "start": try encoded(trace.start), "end": try encoded(trace.end), "width": .int(trace.width ?? board.rules.traceWidth), "usesDefaultWidth": .bool(trace.width == nil), "layer": .int(trace.layer), "net": net(trace.net), "readOnly": .bool(projection.owners[.trace(i)] != nil), "module": owner(.trace(i))]
		}
		let vias = try board.vias.enumerated().map { i, via -> MCPJSON in
			["object": .string(handle(.via(i))), "at": try encoded(via.at), "drill": .int(board.rules.viaDrill), "diameter": .int(board.rules.viaPad), "net": net(via.net), "readOnly": .bool(projection.owners[.via(i)] != nil), "module": owner(.via(i))]
		}
		let holes = try board.holes.enumerated().map { i, hole -> MCPJSON in
			["object": .string(handle(.hole(i))), "at": try encoded(hole.at), "diameter": .int(hole.diameter), "readOnly": .bool(projection.owners[.hole(i)] != nil), "module": owner(.hole(i))]
		}
		let modules = try design.modules.map { module -> MCPJSON in
			let pins = try module.symbol.placedPins.map { pin -> MCPJSON in
				let assignment = projection.schematicNets[pin.at]
				return ["number": .string(pin.number), "name": .string(pin.name), "at": try encoded(pin.at), "direction": .int(pin.direction.degrees), "label": pin.netLabel.map { .string($0) } ?? .null, "net": net(assignment)]
			}
			return ["object": .string(handle(.module(module.id))), "reference": .string(module.reference), "source": .string(module.name), "filename": .string(module.filename),
				"schematicAt": try encoded(module.schematicAt), "schematicRotation": .int(module.schematicRotation.degrees), "layoutAt": try encoded(module.layoutAt), "layoutRotation": .int(module.layoutRotation.degrees),
				"size": try encoded(module.size), "bounds": try encoded(module.bounds), "layers": .int(module.layerCount), "pins": .array(pins), "parameters": try encoded(module.parameters), "parameterValues": try encoded(module.parameterValues),
				"error": design.moduleStatus(module.id).map { .string($0) } ?? .null]
		}
		var result = summary().objectValue!
		result["revision"] = .int(revision)
		result.merge([
			"units": "micrometres", "rotationUnits": "degrees", "layerIndexBase": 0,
			"boardSize": try encoded(board.size), "sheetSize": try encoded(board.sheetSize), "layers": .int(board.stack.count), "layerRoles": try encoded(board.stack.roles), "solderMask": .bool(board.solderMask), "rules": try encoded(board.rules),
			"parts": .array(parts), "wires": .array(wires), "traces": .array(traces), "vias": .array(vias), "holes": .array(holes), "modules": .array(modules),
			"nets": try encoded(projection.design.nets), "parameters": try encoded(design.parameters), "moduleErrors": try encoded(design.moduleErrors), "notices": try encoded(design.moduleCache.notices),
			"schematicDiagnostics": try encoded(schematicDiagnostics(design))
		]) { _, new in new }
		return .object(result)
	}

	func diagnostics(design inspectedDesign: Design? = nil) throws -> MCPJSON {
		refresh()
		let design = inspectedDesign ?? design
		let resolved = design.resolved
		let connectivity = resolved.board.connectivity(planes: resolved.planes)
		let violations = try design.check().map { try diagnostic($0, design: resolved) }
		let islands = try connectivity.islands.map { island -> MCPJSON in
			let terminals = try island.terminals.map { terminal -> MCPJSON in
				var value: [String: MCPJSON] = ["object": .string(handle(terminal.ref)), "points": try MCPJSON(terminal.points), "layers": .array(terminal.layers.map { .int($0) })]
				if case let .pad(part, pad) = terminal.ref {
					value["reference"] = .string(resolved.board.footprints[part].reference)
					value["pin"] = .string(resolved.board.footprints[part].placedPads[pad].name)
				}
				return .object(value)
			}
			return ["id": .string(handle("island", String(island.id))), "net": netValue(island.net, design: resolved), "terminals": .array(terminals), "planeLayers": .array(island.planeLayers.map { .int($0) })]
		}
		let connections = try connectivity.connections().enumerated().map { index, connection -> MCPJSON in
			["id": .string(handle("connection", String(index))), "net": netValue(connection.net, design: resolved),
				"from": .string(handle("island", String(connection.from))), "to": connection.to.map { .string(handle("island", String($0))) } ?? .null,
				"start": try MCPJSON(connection.start), "end": try connection.end.map { try MCPJSON($0) } ?? .null,
				"planeLayers": .array(connection.planeLayers.map { .int($0) })]
		}
		return ["documentId": .string(id.uuidString), "revision": .int(revision), "units": "micrometres", "violations": .array(violations), "islands": .array(islands), "connections": .array(connections), "moduleErrors": try MCPJSON(design.moduleErrors), "schematicDiagnostics": try MCPJSON(schematicDiagnostics(design))]
	}

	func netValue(_ id: Net.ID, design: Design) -> MCPJSON {
		["id": .int(id), "name": design.nets.first { $0.id == id }.map { .string($0.name) } ?? .null]
	}

	func diagnostic(_ violation: Violation, design: Design) throws -> MCPJSON {
		["kind": .string(String(describing: violation.kind)), "message": .string(violation.text), "at": try MCPJSON(violation.at),
			"layer": violation.layer.map { .int($0) } ?? .null,
			"objects": .array((violation.preciseRefs ?? violation.refs).sorted(by: Ref.order).map { .string(handle($0)) }),
			"owners": .array(violation.refs.sorted(by: Ref.order).map { .string(handle($0)) }),
			"nets": .array(violation.nets.sorted().map { netValue($0, design: design) }),
			"measured": violation.measured.map { .double($0) } ?? .null, "required": violation.required.map { .double($0) } ?? .null]
	}

	func netlist() throws -> MCPJSON {
		refresh()
		let resolved = design.moduleProjection(syncNative: true).design
		let parts = resolved.board.footprints.enumerated().map { index, part -> MCPJSON in
			let pins = part.symbol.pins.map { pin -> MCPJSON in
				let net = part.pads.first { $0.name == pin.number }?.net
				return ["number": .string(pin.number), "name": .string(pin.name), "net": net.map { netValue($0, design: resolved) } ?? .null]
			}
			return ["object": .string(handle(.footprint(index))), "reference": .string(part.reference), "component": part.component.map { .string($0.rawValue) } ?? .null, "value": .string(part.value), "pins": .array(pins)]
		}
		return ["documentId": .string(id.uuidString), "revision": .int(revision), "parts": .array(parts), "nets": try MCPJSON(resolved.nets), "moduleErrors": try MCPJSON(design.moduleErrors), "schematicDiagnostics": try MCPJSON(schematicDiagnostics(design))]
	}
}

func schematicDiagnostics(_ design: Design) -> [String] {
	let projection = design.moduleProjection(syncNative: true)
	var diagnostics = projection.report.missingPins.map { "No matching pad: " + $0 }
	if let error = projection.interfaceError { diagnostics.append(error) }
	let sheet = projection.sheet
	for group in Netlist(sheet).groups {
		let labels = Set(group.nodes.compactMap { node in sheet.footprints[node.symbol].symbol.pins[node.pin].netName })
		if labels.count > 1 { diagnostics.append("Conflicting connected net labels: " + labels.sorted().joined(separator: ", ")) }
	}
	return diagnostics
}

extension MCPTools {
	@MainActor
	static func library(_ query: String) throws -> MCPJSON {
		var results: [MCPJSON] = []
		func append(_ spec: MCPJSON, name: String, footprint: Footprint) throws {
			guard query.isEmpty || name.localizedStandardContains(query) else { return }
			let pins = try footprint.symbol.placedPins.map { pin -> MCPJSON in ["number": .string(pin.number), "name": .string(pin.name), "at": try MCPJSON(pin.at)] }
			let pads = try footprint.placedPads.map { pad -> MCPJSON in ["number": .string(pad.name), "at": try MCPJSON(pad.at), "size": try MCPJSON(pad.size), "drill": .int(pad.drill)] }
			results.append(["name": .string(name), "spec": spec, "package": .string(footprint.package.name), "pins": .array(pins), "pads": .array(pads)])
		}
		for component in Component.allCases {
			try append(["component": .string(component.rawValue)], name: component.name, footprint: Footprint(spec: .init(component: component), reference: component.referencePrefix + "1", at: .zero))
		}
		for kind in Symbol.Kind.allCases {
			try append(["symbolKind": .string(kind.rawValue)], name: kind.name, footprint: Footprint(symbol: .init(kind: kind), reference: kind.prefix + "1", at: .zero))
		}
		for kind in Footprint.Kind.allCases {
			let variants = kind == .chip ? Footprint.Chip.allCases : [.c1206]
			for chip in variants {
				let spec = Footprint.Spec(kind: kind, chip: chip)
				try append(["footprintKind": .string(kind.rawValue), "chip": .string(chip.rawValue)], name: spec.summary, footprint: Footprint(spec: spec, reference: spec.referencePrefix + "1", at: .zero))
			}
		}
		return ["results": .array(results), "documents": .array(MCPDocuments.shared.documents.map { $0.summary() })]
	}

	@MainActor
	static func moduleSources(_ entry: MCPDocumentEntry) throws -> MCPJSON {
		let access = try MCPAccess.shared.moduleAccess(for: entry.url)
		defer { access.close() }
		let library = try access.library()
		let current = entry.url?.resolvingSymlinksInPath().standardizedFileURL
		let results = try library.urls.filter { $0 != current }.sorted { $0.path < $1.path }.map { url -> MCPJSON in
			let name = ModuleLibrary.name(of: url.lastPathComponent)
			var probe = Design(board: Board(stack: entry.design.board.stack))
			let id = UUID()
			probe.modules = [ModuleInstance(id: id, reference: "M1", filename: url.lastPathComponent)]
			var resolver = ModuleResolver(folder: current!.deletingLastPathComponent(), library: library, read: access.read)
			resolver.reload(&probe, documentURL: current)
			let module = probe.modules[0]
			return ["name": .string(name), "path": .string(url.path), "interface": try MCPJSON(module.interface), "parameters": try MCPJSON(module.parameters), "size": try MCPJSON(module.size), "layers": .int(module.layerCount), "error": probe.moduleStatus(id).map { .string($0) } ?? .null]
		}
		return ["documentId": .string(entry.id.uuidString), "revision": .int(entry.revision), "sources": .array(results)]
	}
}
