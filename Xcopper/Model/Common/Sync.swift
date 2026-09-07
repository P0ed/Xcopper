import SwiftUI

extension Binding where Value == Design {

	var synchronizingBoard: Binding<Design> {
		Binding(
			get: { wrappedValue },
			set: { next, transaction in
				var next = next
				let previous = wrappedValue
				if next.schematic != previous.schematic
					|| next.modules.map(\.id) != previous.modules.map(\.id)
					|| next.modules.map(\.symbol) != previous.modules.map(\.symbol)
					|| next.moduleCache != previous.moduleCache {
					_ = next.updateBoardFromSchematic()
				}
				if next.board != previous.board || next.modules != previous.modules || next.moduleCache != previous.moduleCache {
					next.inheritConnectedNets()
				}
				self.transaction(transaction).wrappedValue = next
			}
		)
	}
}

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

	mutating func updateBoardFromSchematic() -> Report {
		if !modules.isEmpty {
			let projection = moduleProjection(syncNative: true)
			board.traces = Array(projection.design.board.traces.prefix(board.traces.count))
			board.vias = Array(projection.design.board.vias.prefix(board.vias.count))
			board.footprints = Array(projection.design.board.footprints.prefix(board.footprints.count))
			nets = projection.design.nets
			return projection.report
		}

		let netlist = Netlist(schematic)
		var report = Report()
		var placed: [String: Int] = [:]
		var wired: Set<String> = []
		var usedNames = Set(netlist.groups.compactMap(\.name))

		for (index, footprint) in board.footprints.enumerated()
		where placed[footprint.reference] == nil {
			placed[footprint.reference] = index
		}

		let groups = netlist.groups.map { ($0, $0.pinNames(in: schematic)) }
			.sorted { $0.1.lexicographicallyPrecedes($1.1) }
		for (group, pins) in groups {
			let nodes = group.nodes
				.sorted { ($0.symbol, $0.pin) < ($1.symbol, $1.pin) }

			guard nodes.count > 1 || group.name != nil, !nodes.isEmpty else { continue }

			let existingNames = nodes.flatMap { node -> [String] in
				let symbol = schematic.symbols[node.symbol]
				guard let footprint = placed[symbol.reference] else { return [] }
				let number = symbol.pins[node.pin].number
				return board.footprints[footprint].pads
					.filter { $0.name == number }
					.compactMap { net($0.net)?.name }
			}
			let existingName = existingNames.sorted().first { $0.hasPrefix("N$") && !usedNames.contains($0) }
			var name = group.name ?? existingName ?? "N$\(pins.joined(separator: "/"))"
			if group.name == nil && existingName == nil {
				let base = name
				var suffix = 2
				while usedNames.contains(name) {
					name = "\(base)/\(suffix)"
					suffix += 1
				}
			}
			usedNames.insert(name)
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

	var footprint: Footprint.Spec {
		if let component { return Footprint.Spec(component: component) }

		return switch kind {
		case .resistor, .capacitor, .inductor, .diode: Footprint.Spec(kind: .chip, device: kind.device)
		case .transistor: Footprint.Spec(kind: .sot23)
		case .ic: Footprint.Spec(kind: .soic, pins: pins + pins % 2)
		}
	}
}

extension Footprint.Spec {

	var symbol: Symbol.Spec {
		if let component { return Symbol.Spec(kind: component.symbolKind, component: component) }

		return Symbol.Spec(kind: device.symbolKind, pins: package.makeFootprint()?.pads.count ?? pins)
	}
}

extension Design {

	func symbols(at refs: [Schematic.Ref]) -> [Symbol] {
		refs.compactMap { ref in
			guard case let .symbol(index) = ref, schematic.symbols.indices.contains(index)
			else { return nil }
			return schematic.symbols[index]
		}
	}

	func footprints(at refs: [Ref]) -> [Footprint] {
		refs.compactMap { ref in
			guard case let .footprint(index) = ref, board.footprints.indices.contains(index)
			else { return nil }
			return board.footprints[index]
		}
	}

	func values(of refs: [Schematic.Ref]) -> [String] { symbols(at: refs).map(\.value) }

	func values(of refs: [Ref]) -> [String] { footprints(at: refs).map(\.value) }

	mutating func setValue(_ refs: [Schematic.Ref], to value: String) {
		setValue(of: Set(symbols(at: refs).map(\.reference)), to: value)
	}

	mutating func setValue(_ refs: [Ref], to value: String) {
		setValue(of: Set(footprints(at: refs).map(\.reference)), to: value)
	}

	private mutating func setValue(of references: Set<String>, to value: String) {
		updateParts(references, symbol: { $0.value = value }, footprint: { $0.value = value })
	}

	mutating func rename(_ reference: String, to value: String) {
		guard value != reference else { return }
		updateParts([reference], symbol: { $0.reference = value }, footprint: { $0.reference = value })
	}

	private mutating func updateParts(
		_ references: Set<String>,
		symbol updateSymbol: (inout Symbol) -> Void,
		footprint updateFootprint: (inout Footprint) -> Void
	) {
		guard !references.isEmpty else { return }
		schematic.symbols.modifyEach { symbol in
			if references.contains(symbol.reference) { updateSymbol(&symbol) }
		}
		board.footprints.modifyEach { footprint in
			if references.contains(footprint.reference) { updateFootprint(&footprint) }
		}
	}
}

extension Design {

	var usedReferences: Set<String> {
		Set(schematic.symbols.map(\.reference))
			.union(board.footprints.map(\.reference))
			.union(modules.map(\.reference))
	}

	func nextReference(like reference: String) -> String {
		Xcopper.nextReference(like: reference, used: usedReferences)
	}

	@discardableResult
	mutating func place(_ spec: Symbol.Spec, at point: Point) -> Schematic.Ref {
		let reference = nextReference(like: spec.referencePrefix)
		let symbol = Symbol(spec: spec, reference: reference, at: point)
		schematic.symbols.append(symbol)

		park(modifying(Footprint(spec: spec.footprint, reference: reference, at: .zero)) { footprint in
			footprint.value = symbol.value
		}, as: reference)
		return .symbol(schematic.symbols.count - 1)
	}

	@discardableResult
	mutating func place(_ spec: Footprint.Spec, at point: Point) -> Ref {
		let reference = nextReference(like: spec.referencePrefix)
		let footprint = Footprint(spec: spec, reference: reference, at: point)
		board.footprints.append(footprint)

		park(modifying(Symbol(spec: spec.symbol, reference: reference, at: .zero)) { symbol in
			symbol.value = footprint.value
		}, as: reference)
		return .footprint(board.footprints.count - 1)
	}

	func symbol(of reference: String) -> Symbol? {
		schematic.symbols.first { $0.reference == reference }
	}

	func footprint(of reference: String) -> Footprint? {
		board.footprints.first { $0.reference == reference }
	}

	mutating func park(_ symbol: Symbol?, as reference: String) {
		var taken = schematic.occupied
		park(symbol, as: reference, clear: &taken)
	}

	mutating func park(_ footprint: Footprint?, as reference: String) {
		var taken = board.occupied
		park(footprint, as: reference, clear: &taken)
	}

	mutating func park(_ symbol: Symbol?, as reference: String, clear taken: inout [Rect]) {
		guard let symbol else { return }
		let placed = modifying(symbol) { symbol in
			symbol.reference = reference
			symbol.at = schematic.parking(for: symbol, clear: taken)
		}
		taken.append(placed.placedExtent)
		schematic.symbols.append(placed)
	}

	mutating func park(_ footprint: Footprint?, as reference: String, clear taken: inout [Rect]) {
		guard let footprint else { return }
		let placed = modifying(footprint) { footprint in
			footprint.reference = reference
			footprint.at = board.parking(for: footprint, clear: taken)
		}
		taken.append(placed.placedExtent)
		board.footprints.append(placed)
	}
}

extension Design {

	func footprints(for selection: Set<Schematic.Ref>) -> Set<Ref> {
		let references = Set(symbols(at: Array(selection)).map(\.reference))
		return Set(
			board.footprints.indices
				.filter { references.contains(board.footprints[$0].reference) }
				.map(Ref.footprint)
		).union(selection.moduleIDs.map(Ref.module))
	}

	func symbols(for selection: Set<Ref>) -> Set<Schematic.Ref> {
		let references = Set(footprints(at: Array(selection)).map(\.reference))
		return Set(
			schematic.symbols.indices
				.filter { references.contains(schematic.symbols[$0].reference) }
				.map(Schematic.Ref.symbol)
		).union(selection.moduleIDs.map(Schematic.Ref.module))
	}
}
