struct Design: Equatable, Codable {
	var nets: [Net]
	var board: Board
	var schematic: Schematic
	var modules: [ModuleInstance] = []
	// Value snapshots participate in undo, but are never embedded in saved files.
	var moduleCache = ModuleCache()

	enum CodingKeys: String, CodingKey { case nets, board, schematic, modules }

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		nets = try values.decode([Net].self, forKey: .nets)
		board = try values.decode(Board.self, forKey: .board)
		schematic = try values.decode(Schematic.self, forKey: .schematic)
		modules = try values.decodeIfPresent([ModuleInstance].self, forKey: .modules) ?? []
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
	}

	func net(_ id: Net.ID?) -> Net? {
		id.flatMap { id in nets.first { $0.id == id } }
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

	mutating func renameNet(_ id: Net.ID, to name: String) {
		nets.modifyEach { net in if net.id == id { net.name = name } }
	}

	mutating func net(named name: String) -> (id: Net.ID, created: Bool) {
		if let existing = nets.first(where: { $0.name == name }) { return (existing.id, false) }
		return (addNet(name: name), true)
	}

	var nextAnonymousName: String {
		let used = Set(nets.map(\.name))
		var index = 1
		while used.contains("N$\(index)") { index += 1 }
		return "N$\(index)"
	}
}
