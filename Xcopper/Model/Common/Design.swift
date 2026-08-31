/// One document: a net table, the layout that carries it, and the schematic
/// that defines it.
struct Design: Equatable, Codable {
	var nets: [Net]
	var board: Board
	var schematic: Schematic
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

	var nextNetID: Net.ID { (nets.map(\.id).max() ?? -1) + 1 }

	mutating func addNet(name: String) -> Net.ID {
		let net = Net(id: nextNetID, name: name)
		nets.append(net)
		return net.id
	}

	mutating func removeNet(_ id: Net.ID) {
		nets.removeAll { $0.id == id }
		board.clearNet(id)
	}

	mutating func renameNet(_ id: Net.ID, to name: String) {
		nets.modifyEach { net in if net.id == id { net.name = name } }
	}

	/// The net called `name`, created if the design does not have one yet
	mutating func net(named name: String) -> (id: Net.ID, created: Bool) {
		if let existing = nets.first(where: { $0.name == name }) { return (existing.id, false) }
		return (addNet(name: name), true)
	}

	/// First `N$n` free in the net table
	var nextAnonymousName: String {
		let used = Set(nets.map(\.name))
		var index = 1
		while used.contains("N$\(index)") { index += 1 }
		return "N$\(index)"
	}
}
