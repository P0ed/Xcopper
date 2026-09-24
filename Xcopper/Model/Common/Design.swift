struct Design: Equatable, Codable {
	var nets: [Net] { didSet { projectionCache = ModuleProjectionCache() } }
	var board: Board { didSet { synchronizeParameters(); projectionCache = ModuleProjectionCache() } }
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

	enum CodingKeys: String, CodingKey { case nets, board, modules, parameters }

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		nets = try values.decode([Net].self, forKey: .nets)
		board = try values.decode(Board.self, forKey: .board)
		modules = try values.decodeIfPresent([ModuleInstance].self, forKey: .modules) ?? []
		parameters = try values.decodeIfPresent([ModuleParameter].self, forKey: .parameters) ?? []
		let legacy = try decoder.container(keyedBy: LegacyKeys.self)
		if let sheet = try legacy.decodeIfPresent(LegacySheet.self, forKey: .schematic) {
			migrate(sheet)
		}
		synchronizeParameters()
		if board.footprints.contains(where: { $0.component != nil }) {
			_ = updateBoardFromSchematic()
		}
	}
}

extension Design {

	init(board: Board = Board()) {
		nets = [
			Net(id: 0, name: "GND"),
			Net(id: 1, name: "VCC"),
			Net(id: 2, name: "VEE"),
		]
		self.board = board
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
		let names = Set((board.symbols + modules.map(\.symbol)).flatMap { $0.pins.compactMap(\.netName) })
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

private enum LegacyKeys: String, CodingKey { case schematic }

private struct LegacySheet: Decodable {
	var size: Size
	var wires: [Wire]
	var symbols: [LegacySymbol]
}

private struct LegacySymbol: Decodable {
	var reference: String
	var value: String
	var kind: Symbol.Kind
	var component: Component?
	var symbol: Symbol

	enum CodingKeys: String, CodingKey { case reference, value, kind, component }

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		reference = try values.decode(String.self, forKey: .reference)
		value = try values.decode(String.self, forKey: .value)
		kind = try values.decode(Symbol.Kind.self, forKey: .kind)
		component = try values.decodeIfPresent(Component.self, forKey: .component)
		symbol = try Symbol(from: decoder)
	}
}

private extension Design {
	mutating func migrate(_ sheet: LegacySheet) {
		var board = self.board
		board.sheetSize = sheet.size
		board.wires = sheet.wires
		var matched: Set<Int> = []
		for legacy in sheet.symbols {
			let index: Int
			if let existing = board.footprints.indices.first(where: {
				!matched.contains($0) && board.footprints[$0].reference == legacy.reference
			}) {
				index = existing
			} else {
				let spec = Symbol.Spec(kind: legacy.kind, pins: legacy.symbol.pins.count, component: legacy.component)
				var footprint = Footprint(spec: spec.footprint, reference: legacy.reference, at: .zero)
				footprint.at = board.parking(for: footprint, clear: board.occupied)
				index = board.footprints.count
				board.footprints.append(footprint)
			}
			board.footprints[index].symbol = legacy.symbol
			board.footprints[index].value = legacy.value
			matched.insert(index)
		}
		var taken = board.schematicOccupied
		for index in board.footprints.indices where !matched.contains(index) {
			board.footprints[index].symbol.at = board.parking(for: board.footprints[index].symbol, clear: taken)
			taken.append(board.footprints[index].symbol.placedExtent)
		}
		self.board = board
	}
}
