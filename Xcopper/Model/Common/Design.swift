struct Design: Equatable, Codable {
	var nets: [Net] { didSet { projectionCache = ModuleProjectionCache() } }
	var board: Board { didSet { projectionCache = ModuleProjectionCache() } }
	var schematic: Schematic { didSet { synchronizeParameters(); projectionCache = ModuleProjectionCache() } }
	var modules: [ModuleInstance] = [] { didSet { synchronizeParameters(); projectionCache = ModuleProjectionCache() } }
	var parameters: [ModuleParameter] = [] { didSet { projectionCache = ModuleProjectionCache() } }
	var moduleCache = ModuleCache() { didSet { projectionCache = ModuleProjectionCache() } }
	private var projectionCache = ModuleProjectionCache()

	func moduleProjection(syncNative: Bool = false, resolvingParameters: Bool = true) -> ModuleProjection {
		if modules.isEmpty && !syncNative {
			var projection = ModuleProjection(design: self)
			if resolvingParameters { applyParameterDefaults(to: &projection.design.board) }
			return projection
		}
		return projectionCache.value(syncNative: syncNative, resolvingParameters: resolvingParameters) {
			buildModuleProjection(syncNative: syncNative, resolvingParameters: resolvingParameters)
		}
	}

	enum CodingKeys: String, CodingKey { case nets, board, schematic, modules, parameters }

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		nets = try values.decode([Net].self, forKey: .nets)
		board = try values.decode(Board.self, forKey: .board)
		schematic = try values.decode(Schematic.self, forKey: .schematic)
		modules = try values.decodeIfPresent([ModuleInstance].self, forKey: .modules) ?? []
		parameters = try values.decodeIfPresent([ModuleParameter].self, forKey: .parameters) ?? []
		synchronizeParameters()
		if board.footprints.contains(where: { $0.component != nil }) {
			_ = updateBoardFromSchematic()
		}
	}
}

extension Design {

	init(board: Board = Board(), schematic: Schematic = Schematic()) {
		nets = [
			Net(id: 0, name: "GND"),
			Net(id: 1, name: "VCC"),
			Net(id: 2, name: "VEE"),
		]
		self.board = board
		self.schematic = schematic
		synchronizeParameters()
	}

	func net(_ id: Net.ID?) -> Net? {
		id.flatMap { id in resolved.nets.first { $0.id == id } }
	}

	func plane(_ layer: Int) -> Net.ID? {
		board.stack.plane(of: layer).flatMap { name in nets.first { $0.name == name }?.id }
	}

	var planes: [Net.ID?] { board.stack.copper.map { layer in plane(layer) } }

	func isPlaneNet(_ id: Net.ID) -> Bool {
		net(id).map { net in board.stack.planeNames.contains(net.name) } ?? false
	}

	mutating func restack(_ stack: Stack) {
		guard canRestack(stack) else { return }
		board.restack(stack)
		for name in stack.planeNames { _ = net(named: name) }
	}

	var nextNetID: Net.ID { (nets.map(\.id).max() ?? -1) + 1 }

	mutating func addNet(name: String) -> Net.ID {
		let net = Net(id: nextNetID, name: name)
		nets.append(net)
		return net.id
	}

	mutating func removeNet(_ id: Net.ID) {
		guard !isPlaneNet(id) else { return }
		nets.removeAll { $0.id == id }
		board.clearNet(id)
	}

	mutating func removeUnusedNets() {
		var used = Set(board.traces.compactMap(\.net))
		used.formUnion(board.vias.compactMap(\.net))
		for footprint in board.footprints { used.formUnion(footprint.pads.compactMap(\.net)) }
		let names = Set((schematic.symbols + modules.map(\.symbol)).flatMap { $0.pins.compactMap(\.netName) })
			.union(supplyNames).union(board.stack.planeNames)
		nets.removeAll { !used.contains($0.id) && !names.contains($0.name) }
	}

	mutating func renameNet(_ id: Net.ID, to name: String) {
		nets.modifyEach { net in if net.id == id { net.name = name } }
	}

	mutating func net(named name: String) -> (id: Net.ID, created: Bool) {
		if let existing = nets.first(where: { $0.name == name }) { return (existing.id, false) }
		let projection = moduleProjection()
		if let existing = projection.design.nets.first(where: { $0.name == name && projection.localNets.contains($0.id) }) {
			return (existing.id, false)
		}
		return (addNet(name: name), true)
	}
}
