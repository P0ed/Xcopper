func touches(_ point: Point, _ wire: Wire) -> Bool {
	distance(from: point, to: wire.start, wire.end) <= 1000.0
}

struct Netlist {

	struct Node: Hashable {
		var symbol: Int
		var pin: Int
	}

	struct Group: Equatable {
		var name: String?
		var nodes: Set<Node>
		var points: Set<Point>
	}

	var groups: [Group] = []
	private var index: [Point: Int] = [:]

	func group(at point: Point) -> Group? {
		index[point].map { groups[$0] }
	}

	func name(at point: Point) -> String? {
		group(at: point)?.name
	}
}

extension Netlist {

	init(_ schematic: Schematic) {
		var merge = UnionFind<Point>()
		var terminals: Set<Point> = []

		for wire in schematic.wires {
			terminals.insert(wire.start)
			terminals.insert(wire.end)
			merge.union(wire.start, wire.end)
		}
		for symbol in schematic.symbols {
			for pin in symbol.placedPins { terminals.insert(pin.at) }
		}
		for label in schematic.labels {
			terminals.insert(label.at)
		}

		for point in terminals {
			for wire in schematic.wires where touches(point, wire) {
				merge.union(point, wire.start)
			}
		}

		var order: [Point: Int] = [:]
		var groups: [Group] = []

		func bucket(_ point: Point) -> Int {
			let root = merge.find(point)
			if let existing = order[root] { return existing }
			order[root] = groups.count
			groups.append(Group(name: nil, nodes: [], points: []))
			return groups.count - 1
		}

		var index: [Point: Int] = [:]
		for point in terminals.sorted(by: Point.order) {
			let slot = bucket(point)
			index[point] = slot
			groups[slot].points.insert(point)
		}

		for (symbolIndex, symbol) in schematic.symbols.enumerated() {
			for (pinIndex, pin) in symbol.placedPins.enumerated() {
				groups[bucket(pin.at)].nodes.insert(Node(symbol: symbolIndex, pin: pinIndex))
			}
		}

		var labelled: [Int: String] = [:]
		for label in schematic.labels {
			let text = label.text.trimmingWhitespace
			guard !text.isEmpty else { continue }
			let slot = bucket(label.at)
			labelled[slot] = min(labelled[slot] ?? text, text)
		}
		for (slot, net) in labelled { groups[slot].name = net }

		self.groups = groups
		self.index = index
	}
}

extension Point {

	static func order(_ lhs: Point, _ rhs: Point) -> Bool {
		lhs.y != rhs.y ? lhs.y < rhs.y : lhs.x < rhs.x
	}
}

extension Schematic {

	var junctions: [Point] {
		var terminals: Set<Point> = []
		for wire in wires {
			terminals.insert(wire.start)
			terminals.insert(wire.end)
		}
		for symbol in symbols {
			for pin in symbol.placedPins { terminals.insert(pin.at) }
		}
		for label in labels { terminals.insert(label.at) }

		return terminals.filter { point in
			var legs = 0
			for wire in wires {
				if wire.start == point || wire.end == point {
					legs += 1
				} else if touches(point, wire) {
					legs += 2
				}
			}
			for symbol in symbols {
				legs += symbol.placedPins.count { pin in pin.at == point }
			}
			return legs >= 3
		}
		.sorted(by: Point.order)
	}
}
