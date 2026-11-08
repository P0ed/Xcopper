struct Rat: Hashable {
	var from: Point
	var to: Point
	var net: Net.ID
}

struct Strand: Hashable {
	var at: Point
	var net: Net.ID
}

extension Board {
	func ratsnest(planes: [Net.ID?] = []) -> [Rat] {
		connectivity(planes: planes).connections(terminalsOnly: true).compactMap { connection in
			connection.end.map { Rat(from: connection.start, to: $0, net: connection.net) }
		}
	}

	func stranded(planes: [Net.ID?]) -> [Strand] {
		guard planes.contains(where: { $0 != nil }) else { return [] }
		return connectivity(planes: planes).connections(terminalsOnly: true).filter { $0.to == nil }.map { Strand(at: $0.start, net: $0.net) }
	}
}
