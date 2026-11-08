import Foundation
import MCP

struct MCPConnectionProposal {
	var revision: Int
	var candidate: Design
	var created: Date
}

private struct PhysicalFault: Hashable {
	var kind: Violation.Kind
	var at: Point
	var layer: Int?
	var nets: Set<Net.ID>
	var measured: Double?
	var required: Double?
	init(_ violation: Violation) {
		kind = violation.kind; at = violation.at; layer = violation.layer; nets = violation.nets
		measured = violation.measured; required = violation.required
	}
}

@MainActor
extension MCPTools {
	static func planConnection(_ args: MCPArguments, entry: MCPDocumentEntry) async throws -> MCPJSON {
		try entry.requireRevision(args)
		let revision = entry.revision
		let original = entry.design
		guard original.moduleErrors.isEmpty else { throw MCPFailure("unresolved_modules", "Resolve module errors before planning a connection.") }
		let resolved = original.resolved
		let connectivity = resolved.board.connectivity(planes: resolved.planes)
		func index(_ text: String, kind: String) throws -> Int {
			let prefix = entry.handle(kind, "")
			guard text.hasPrefix(prefix), let index = Int(text.dropFirst(prefix.count)) else { throw MCPFailure("invalid_endpoint", "Use a current \(kind) handle from check_design.") }
			return index
		}
		func endpoint(_ text: String) throws -> CopperIsland {
			if text.hasPrefix(entry.handle("island", "")) {
				let id = try index(text, kind: "island")
				guard let island = connectivity.islands.first(where: { $0.id == id }) else { throw MCPFailure("invalid_endpoint", "The copper island was not found.") }
				return island
			}
			let refs = try entry.layoutRefs([text], in: original, editable: false)
			guard let ref = refs.first, [.pad, .trace, .via].contains(ref.kind), var island = connectivity.islands.first(where: { $0.terminals.contains { $0.ref == ref } }) else { throw MCPFailure("invalid_endpoint", "Endpoints require an assigned pad, trace, via or copper island.") }
			island.terminals = island.terminals.filter { $0.ref == ref }
			return island
		}
		let from: CopperIsland
		let to: CopperIsland?
		if let connection = args.values["connection"]?.stringValue {
			guard args.values["from"] == nil, args.values["to"] == nil else { throw MCPFailure("invalid_arguments", "Specify either connection or from/to endpoints.") }
			let connections = connectivity.connections()
			let i = try index(connection, kind: "connection")
			guard connections.indices.contains(i) else { throw MCPFailure("invalid_endpoint", "The connection was not found.") }
			let selected = connections[i]
			from = connectivity.islands[selected.from]
			to = selected.to.map { connectivity.islands[$0] }
		} else {
			from = try endpoint(args.string("from"))
			let target = try args.string("to")
			to = target == "plane" ? nil : try endpoint(target)
		}
		guard to == nil || to!.net == from.net else { throw MCPFailure("incompatible_nets", "Connection endpoints must belong to the same resolved net.") }
		if to == nil, !resolved.planes.contains(from.net) { throw MCPFailure("invalid_endpoint", "The source net has no plane in this stackup.") }
		let layers = args.values["layers"]?.arrayValue?.compactMap(\.intValue) ?? resolved.board.stack.signals
		let request = ConnectionRoutingRequest(board: resolved.board, from: from, to: to, layers: Array(Set(layers)).sorted(),
			width: args.values["width"]?.intValue ?? resolved.board.rules.traceWidth,
			clearance: args.values["clearance"]?.intValue ?? resolved.board.rules.clearance,
			viaLimit: args.values["viaLimit"]?.intValue ?? 4, grid: args.values["grid"]?.intValue ?? 100,
			maxNodes: args.values["maxNodes"]?.intValue ?? 200_000)
		let worker = Task.detached(priority: .userInitiated) { try ConnectionRouter(request).plan() }
		let route: PlannedConnection
		do {
			route = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
		} catch let failure as ConnectionRoutingFailure {
			throw MCPFailure(failure.code, "Connection planning failed: " + failure.code + ". Adjust the routing grid, layers, rules or search budget.", details: ["visitedNodes": .int(failure.visited)])
		}
		try Task.checkCancellation()
		guard !entry.contexts.isEmpty else { throw MCPFailure("document_not_found", "The document closed while planning.") }
		try entry.requireRevision(args)
		var candidate = original
		candidate.board.traces.append(contentsOf: route.traces)
		candidate.board.vias.append(contentsOf: route.vias)
		candidate.inheritConnectedNets()
		try validate(candidate)
		try validateConnection(candidate, original: original, from: from, to: to)
		entry.proposals = entry.proposals.filter { Date().timeIntervalSince($0.value.created) < 600 && $0.value.revision == revision }
		if entry.proposals.count >= 8, let oldest = entry.proposals.min(by: { $0.value.created < $1.value.created })?.key { entry.proposals[oldest] = nil }
		let id = UUID()
		entry.proposals[id] = MCPConnectionProposal(revision: revision, candidate: candidate, created: Date())
		let violations = try candidate.check().map { withoutHandles(try entry.diagnostic($0, design: candidate.resolved), document: entry.id.uuidString) }
		return ["documentId": .string(entry.id.uuidString), "revision": .int(revision), "proposalId": .string(entry.handle("proposal", id.uuidString)),
			"units": "micrometres", "net": entry.netValue(from.net, design: resolved), "traces": try MCPJSON(route.traces), "vias": try MCPJSON(route.vias),
			"length": .double(route.length), "visitedNodes": .int(route.visited), "connected": true, "newViolations": [], "violations": .array(violations), "expiresInSeconds": 600]
	}

	static func validateConnection(_ candidate: Design, original: Design, from: CopperIsland, to: CopperIsland?) throws {
		var baseline: [PhysicalFault: Int] = [:]
		for fault in original.faults() { baseline[PhysicalFault(fault), default: 0] += 1 }
		for fault in candidate.faults() {
			let key = PhysicalFault(fault)
			guard baseline[key, default: 0] > 0 else {
				throw MCPFailure("routing_violations", "The proposed connection introduces a physical design-rule fault: " + fault.text,
					details: ["kind": .string(String(describing: fault.kind)), "at": try MCPJSON(fault.at), "measured": fault.measured.map { .double($0) } ?? .null, "required": fault.required.map { .double($0) } ?? .null])
			}
			baseline[key, default: 0] -= 1
		}
		let resolved = candidate.resolved
		let connectivity = resolved.board.connectivity(planes: resolved.planes)
		func containing(_ original: CopperIsland) -> CopperIsland? {
			guard let terminal = original.terminals.first else { return nil }
			return connectivity.islands.first { island in island.net == original.net && island.terminals.contains { $0.figure == terminal.figure && $0.layers == terminal.layers } }
		}
		guard let source = containing(from), to.map({ containing($0)?.id == source.id }) ?? !source.planeLayers.isEmpty else { throw MCPFailure("connection_incomplete", "The candidate copper does not complete the requested connection.") }
	}

	static func applyConnection(_ args: MCPArguments, entry: MCPDocumentEntry) throws -> MCPJSON {
		try entry.requireIdle()
		try entry.requireRevision(args)
		let (id, proposal) = try connectionProposal(args.string("proposalId"), entry: entry)
		let before = try entry.inspection()
		let objects = nativeAddresses(entry.design, entry: entry)
		try Task.checkCancellation()
		try entry.commit(proposal.candidate, name: "AI: connect copper")
		entry.proposals[id] = nil
		return try mutationResponse(entry, before: before, objects: objects, compact: args.values["response"] != "full")
	}

	static func connectionProposal(_ supplied: String, entry: MCPDocumentEntry) throws -> (UUID, MCPConnectionProposal) {
		let prefix = entry.handle("proposal", "")
		guard supplied.hasPrefix(prefix), let id = UUID(uuidString: String(supplied.dropFirst(prefix.count))),
			let proposal = entry.proposals[id], proposal.revision == entry.revision, Date().timeIntervalSince(proposal.created) < 600 else { throw MCPFailure("invalid_proposal", "The proposal expired, was applied, or belongs to another revision. Plan the connection again.") }
		return (id, proposal)
	}
}
