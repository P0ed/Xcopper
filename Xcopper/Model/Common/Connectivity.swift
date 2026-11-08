struct CopperTerminal: Hashable {
	var ref: Ref
	var figure: Figure
	var layers: ClosedRange<Int>
	var net: Net.ID

	var points: [Point] {
		switch figure {
		case let .segment(start, end, _): [start, end]
		case let .round(at, _): [at]
		case let .rect(rect): [rect.center]
		}
	}
}

struct CopperIsland {
	var id: Int
	var net: Net.ID
	var terminals: [CopperTerminal]
	var planeLayers: [Int]
	var points: [Point] { terminals.flatMap(\.points) }
	var hasTerminal: Bool { terminals.contains { $0.ref.kind != .trace } }
}

struct CopperConnection {
	var net: Net.ID
	var from: Int
	var to: Int? = nil
	var start: Point
	var end: Point? = nil
	var planeLayers: [Int] = []
}

struct CopperConnectivity {
	var islands: [CopperIsland]
	var planes: [Net.ID?]

	func connections(terminalsOnly: Bool = false) -> [CopperConnection] {
		let eligible = islands.filter { !terminalsOnly || $0.hasTerminal }
		var result: [CopperConnection] = []
		for net in Set(eligible.map(\.net)).sorted() {
			var loose = eligible.filter { $0.net == net }
			guard let first = loose.first else { continue }
			loose.removeFirst()
			var tree = [first]
			while !loose.isEmpty {
				var best: (distance: Int, index: Int, connection: CopperConnection)?
				for island in tree {
					for (index, target) in loose.enumerated() {
						for start in island.points {
							for end in target.points {
								let distance = start.distanceSquared(to: end)
								if distance < (best?.distance ?? Int.max) {
									best = (distance, index, CopperConnection(net: net, from: island.id, to: target.id, start: start, end: end))
									}
							}
						}
					}
				}
				guard let best else { break }
				result.append(best.connection)
				tree.append(loose.remove(at: best.index))
			}
		}
		for island in eligible where island.planeLayers.isEmpty {
			let layers = planes.indices.filter { planes[$0] == island.net }
			if !layers.isEmpty, let point = island.points.first {
				result.append(CopperConnection(net: island.net, from: island.id, start: point, planeLayers: layers))
			}
		}
		return result
	}
}

extension Board {
	func connectivity(planes: [Net.ID?] = []) -> CopperConnectivity {
		let terminals = objects.compactMap { object -> CopperTerminal? in
			guard !object.drilled, let net = object.net else { return nil }
			return CopperTerminal(ref: object.detailRef, figure: object.figure, layers: object.layers, net: net)
		}
		var merge = UnionFind<Int>()
		for (layer, net) in planes.enumerated() {
			guard let net else { continue }
			for (index, terminal) in terminals.enumerated() where terminal.net == net && terminal.layers.contains(layer) { merge.union(index, terminals.count + layer) }
		}
		let ordered = terminals.indices.sorted { terminals[$0].figure.bounds.minX < terminals[$1].figure.bounds.minX }
		for (position, index) in ordered.enumerated() {
			let terminal = terminals[index]
			for other in ordered.dropFirst(position + 1) {
				let peer = terminals[other]
				if peer.figure.bounds.minX > terminal.figure.bounds.maxX { break }
				guard terminal.net == peer.net, terminal.layers.overlaps(peer.layers), terminal.figure.bounds.intersects(peer.figure.bounds) else { continue }
				if gap(terminal.figure, peer.figure) <= 0.5 { merge.union(index, other) }
			}
		}
		var groups: [Int: [Int]] = [:]
		for index in terminals.indices { groups[merge.find(index), default: []].append(index) }
		let islands = groups.values.sorted { $0[0] < $1[0] }.enumerated().map { id, indices in
			let members = indices.map { terminals[$0] }
			let net = members[0].net
			let layers = planes.indices.filter { layer in planes[layer] == net && members.contains { $0.layers.contains(layer) } }
			return CopperIsland(id: id, net: net, terminals: members, planeLayers: layers)
		}
		return CopperConnectivity(islands: islands, planes: planes)
	}
}
