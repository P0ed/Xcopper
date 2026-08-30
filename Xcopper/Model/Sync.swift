extension Design {

	struct Report: Equatable {
		var assigned: Int = 0
		var created: [String] = []
		var missingFootprints: [String] = []
		var extraFootprints: [String] = []
		var missingPins: [String] = []

		var isClean: Bool {
			missingFootprints.isEmpty && extraFootprints.isEmpty && missingPins.isEmpty
		}
	}

	/// Pushes the schematic's netlist onto the layout, matching footprints by
	/// reference designator and pads by pin number. Additive: a pad the
	/// schematic says nothing about keeps whatever net it already had.
	mutating func updateBoardFromSchematic() -> Report {
		let netlist = Netlist(schematic)
		var report = Report()
		var placed: [String: Int] = [:]
		var wired: Set<String> = []

		for (index, footprint) in board.footprints.enumerated()
		where placed[footprint.reference] == nil {
			placed[footprint.reference] = index
		}

		for group in netlist.groups {
			// Power flags name a net but are not parts, so they never match a footprint
			let nodes = group.nodes
				.filter { node in !schematic.symbols[node.symbol].kind.isPower }
				.sorted { ($0.symbol, $0.pin) < ($1.symbol, $1.pin) }

			guard nodes.count > 1 || group.name != nil, !nodes.isEmpty else { continue }

			let name = group.name ?? nextAnonymousName
			let (id, created) = net(named: name)
			if created { report.created.append(name) }

			for node in nodes {
				let symbol = schematic.symbols[node.symbol]
				let number = symbol.pins[node.pin].number
				wired.insert(symbol.reference)

				guard let footprint = placed[symbol.reference] else { continue }
				guard let pad = board.footprints[footprint].pads
					.firstIndex(where: { $0.name == number })
				else {
					report.missingPins.append("\(symbol.reference).\(number)")
					continue
				}
				board.footprints[footprint].pads[pad].net = id
				report.assigned += 1
			}
		}

		report.missingPins.sort()
		report.missingFootprints = wired.filter { placed[$0] == nil }.sorted()
		report.extraFootprints = board.footprints.map(\.reference)
			.filter { !wired.contains($0) }
			.sorted()
		return report
	}
}
