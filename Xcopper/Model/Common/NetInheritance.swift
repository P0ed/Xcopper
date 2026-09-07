extension Board {

	var inheritedNets: [Ref: Net.ID] {
		let copper = objects.filter { !$0.drilled }
			.sorted { $0.bounds.minX < $1.bounds.minX }
		guard copper.contains(where: { $0.net != nil }) else { return [:] }
		var connections = UnionFind<Int>()
		for (index, object) in copper.enumerated() {
			for other in copper.indices.dropFirst(index + 1) {
				let peer = copper[other]
				guard peer.bounds.minX <= object.bounds.maxX else { break }
				guard object.shared(with: peer) != nil,
					object.bounds.intersects(peer.bounds),
					gap(object.figure, peer.figure) <= 0.5
				else { continue }
				connections.union(index, other)
			}
		}

		var nets: [Int: Set<Net.ID>] = [:]
		for (index, object) in copper.enumerated() {
			if let net = object.net { nets[connections.find(index), default: []].insert(net) }
		}
		var assignments: [Ref: Net.ID] = [:]
		for (index, object) in copper.enumerated()
		where object.net == nil && (object.ref.kind == .trace || object.ref.kind == .via) {
			let connected = nets[connections.find(index)] ?? []
			if connected.count == 1 { assignments[object.ref] = connected.first }
		}
		return assignments
	}
}

extension Design {

	mutating func inheritConnectedNets() {
		guard board.traces.contains(where: { $0.net == nil })
			|| board.vias.contains(where: { $0.net == nil })
		else { return }
		let resolved = resolved
		var inherited: Set<Net.ID> = []
		for (ref, net) in resolved.board.inheritedNets {
			switch ref {
			case let .trace(index) where board.traces.indices.contains(index):
				board.traces[index].net = net
			case let .via(index) where board.vias.indices.contains(index):
				board.vias[index].net = net
			default: continue
			}
			inherited.insert(net)
		}
		for net in resolved.nets where inherited.contains(net.id) && self.net(net.id) == nil {
			nets.append(net)
		}
	}
}
