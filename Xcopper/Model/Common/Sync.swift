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
				let pads = board.footprints[footprint].pads.indices
					.filter { board.footprints[footprint].pads[$0].name == number }
				guard !pads.isEmpty else {
					report.missingPins.append("\(symbol.reference).\(number)")
					continue
				}
				for pad in pads { board.footprints[footprint].pads[pad].net = id }
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

extension Symbol.Spec {

	/// The package a part drawn like this goes in. A power or ground flag names
	/// a net rather than standing for a part, so it has none.
	var footprint: Footprint.Spec? {
		if let component { return Footprint.Spec(component: component) }

		return switch kind {
		case .capacitor: Footprint.Spec(kind: .chip, part: .capacitor)
		case .resistor, .inductor, .diode: Footprint.Spec(kind: .chip)
		case .transistor: Footprint.Spec(kind: .sot23)
		// SOIC rounds an odd pin count down, which would leave the last pin with
		// nowhere to land, so the package is asked for one pad more instead
		case .ic: Footprint.Spec(kind: .soic, pins: pins + pins % 2)
		case .power, .ground: nil
		}
	}
}

extension Footprint.Part {

	/// How a chip is drawn on the sheet
	var symbol: Symbol.Kind {
		switch self {
		case .resistor: .resistor
		case .capacitor: .capacitor
		}
	}
}

extension Footprint.Spec {

	/// The symbol that stands for a part in this package
	var symbol: Symbol.Spec {
		if let component { return Symbol.Spec(kind: component.symbolKind, component: component) }

		return switch kind {
		case .chip: Symbol.Spec(kind: part.symbol)
		case .sot23: Symbol.Spec(kind: .transistor)
		case .soic, .dip: Symbol.Spec(kind: .ic, pins: pins)
		case .header: Symbol.Spec(kind: .ic, pins: pins * rows)
		}
	}
}

extension Design {

	/// A designator free on both halves of the document, so a symbol and the
	/// footprint that goes with it can share one
	func nextReference(like reference: String) -> String {
		Xcopper.nextReference(
			like: reference,
			used: Set(schematic.symbols.map(\.reference))
				.union(board.footprints.map(\.reference))
		)
	}

	/// Draws a symbol on the sheet and stands the footprint that goes with it on
	/// the board, parked where it covers nothing already drawn. Nothing links the
	/// two but the designator they share, which is all `updateBoardFromSchematic`
	/// needs to pair them again.
	@discardableResult
	mutating func place(_ spec: Symbol.Spec, at point: Pt) -> Schematic.Ref {
		let reference = nextReference(like: spec.referencePrefix)
		schematic.symbols.append(Symbol(spec: spec, reference: reference, at: point))

		if let package = spec.footprint {
			let footprint = Footprint(spec: package, reference: reference, at: .zero)
			board.footprints.append(modifying(footprint) { footprint in
				footprint.at = board.parking(for: footprint)
			})
		}
		return .symbol(schematic.symbols.count - 1)
	}

	/// Stands a footprint on the board and draws the symbol that goes with it on
	/// the sheet, the other way about
	@discardableResult
	mutating func place(_ spec: Footprint.Spec, at point: Pt) -> Ref {
		let reference = nextReference(like: spec.referencePrefix)
		board.footprints.append(Footprint(spec: spec, reference: reference, at: point))

		let symbol = Symbol(spec: spec.symbol, reference: reference, at: .zero)
		schematic.symbols.append(modifying(symbol) { symbol in
			symbol.at = schematic.parking(for: symbol)
		})
		return .footprint(board.footprints.count - 1)
	}
}

extension Design {

	/// The parts on the board that stand for the symbols picked on the sheet.
	/// Nothing links the two halves but the designator they share, so they are
	/// paired by name here the way `updateBoardFromSchematic` pairs them.
	func footprints(for selection: Set<Schematic.Ref>) -> Set<Ref> {
		let references = Set(selection.compactMap { ref -> String? in
			guard case let .symbol(index) = ref, schematic.symbols.indices.contains(index)
			else { return nil }
			return schematic.symbols[index].reference
		})
		guard !references.isEmpty else { return [] }

		return Set(
			board.footprints.indices
				.filter { references.contains(board.footprints[$0].reference) }
				.map(Ref.footprint)
		)
	}

	/// The symbols on the sheet that stand for the parts picked on the board,
	/// the other way about
	func symbols(for selection: Set<Ref>) -> Set<Schematic.Ref> {
		let references = Set(selection.compactMap { ref -> String? in
			guard case let .footprint(index) = ref, board.footprints.indices.contains(index)
			else { return nil }
			return board.footprints[index].reference
		})
		guard !references.isEmpty else { return [] }

		return Set(
			schematic.symbols.indices
				.filter { references.contains(schematic.symbols[$0].reference) }
				.map(Schematic.Ref.symbol)
		)
	}
}
