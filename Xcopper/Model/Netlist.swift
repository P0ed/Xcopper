/// Whether `point` lies on `wire`, allowing a nanometre of rounding slack
func touches(_ point: Pt, _ wire: Wire) -> Bool {
	distance(from: point, to: wire.start, wire.end) <= 1000.0
}

/// Connectivity read back out of the drawing: what is wired to what, and under
/// which name. Nothing here is stored in the document.
struct Netlist {

	/// A pin of a placed symbol, by index into `Schematic.symbols` and its `pins`
	struct Node: Hashable {
		var symbol: Int
		var pin: Int
	}

	struct Group: Equatable {
		var name: String?
		var nodes: Set<Node>
		var points: Set<Pt>
	}

	var groups: [Group] = []
	private var index: [Pt: Int] = [:]

	func group(at point: Pt) -> Group? {
		index[point].map { groups[$0] }
	}

	func name(at point: Pt) -> String? {
		group(at: point)?.name
	}
}

private struct Merge {
	private var parent: [Pt: Pt] = [:]

	mutating func find(_ point: Pt) -> Pt {
		guard let up = parent[point] else {
			parent[point] = point
			return point
		}
		guard up != point else { return point }
		let root = find(up)
		parent[point] = root
		return root
	}

	mutating func union(_ a: Pt, _ b: Pt) {
		let (ra, rb) = (find(a), find(b))
		guard ra != rb else { return }
		parent[ra] = rb
	}
}

extension Netlist {

	init(_ schematic: Schematic) {
		var merge = Merge()
		var terminals: Set<Pt> = []

		// Every wire shorts its own two ends
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

		// A terminal sitting anywhere on a wire joins it. Only terminals are
		// tested, so a T-junction connects and an X-crossing does not.
		for point in terminals {
			for wire in schematic.wires where touches(point, wire) {
				merge.union(point, wire.start)
			}
		}

		var order: [Pt: Int] = [:]
		var groups: [Group] = []

		func bucket(_ point: Pt) -> Int {
			let root = merge.find(point)
			if let existing = order[root] { return existing }
			order[root] = groups.count
			groups.append(Group(name: nil, nodes: [], points: []))
			return groups.count - 1
		}

		var index: [Pt: Int] = [:]
		for point in terminals.sorted(by: Pt.order) {
			let slot = bucket(point)
			index[point] = slot
			groups[slot].points.insert(point)
		}

		for (symbolIndex, symbol) in schematic.symbols.enumerated() {
			for (pinIndex, pin) in symbol.placedPins.enumerated() {
				groups[bucket(pin.at)].nodes.insert(Node(symbol: symbolIndex, pin: pinIndex))
			}
		}

		// An explicit label wins over a power flag; ties break alphabetically so
		// the same sheet always yields the same names.
		var supplied: [Int: String] = [:]
		var labelled: [Int: String] = [:]

		for symbol in schematic.symbols {
			guard let net = symbol.suppliedNet, let pin = symbol.placedPins.first else { continue }
			let slot = bucket(pin.at)
			supplied[slot] = min(supplied[slot] ?? net, net)
		}
		for label in schematic.labels {
			let text = label.text.trimmingWhitespace
			guard !text.isEmpty else { continue }
			let slot = bucket(label.at)
			labelled[slot] = min(labelled[slot] ?? text, text)
		}
		for (slot, net) in supplied { groups[slot].name = net }
		for (slot, net) in labelled { groups[slot].name = net }

		self.groups = groups
		self.index = index
	}
}

extension Pt {

	/// Stable ordering, so derived results do not depend on set iteration
	static func order(_ lhs: Pt, _ rhs: Pt) -> Bool {
		lhs.y != rhs.y ? lhs.y < rhs.y : lhs.x < rhs.x
	}
}

extension Schematic {

	/// Points where three or more conductors meet, drawn as junction dots
	var junctions: [Pt] {
		var terminals: Set<Pt> = []
		for wire in wires {
			terminals.insert(wire.start)
			terminals.insert(wire.end)
		}
		for symbol in symbols {
			for pin in symbol.placedPins { terminals.insert(pin.at) }
		}

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
		.sorted(by: Pt.order)
	}
}
