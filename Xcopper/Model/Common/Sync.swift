import SwiftUI

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

		for (index, footprint) in board.footprints.enumerated()
		where placed[footprint.reference] == nil {
			placed[footprint.reference] = index
		}

		for group in netlist.groups {
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

	var footprint: Footprint.Spec? {
		if let component { return Footprint.Spec(component: component) }

		return switch kind {
		case .resistor, .capacitor, .inductor, .diode: Footprint.Spec(kind: .chip, device: kind.device)
		case .transistor: Footprint.Spec(kind: .sot23)
		case .ic: Footprint.Spec(kind: .soic, pins: pins + pins % 2)
		case .power, .ground: nil
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

	func values(of refs: [Schematic.Ref]) -> [String] {
		refs.compactMap { ref in
			guard case let .symbol(index) = ref, schematic.symbols.indices.contains(index)
			else { return nil }
			return schematic.symbols[index].value
		}
	}

	func values(of refs: [Ref]) -> [String] {
		refs.compactMap { ref in
			guard case let .footprint(index) = ref, board.footprints.indices.contains(index)
			else { return nil }
			return board.footprints[index].value
		}
	}

	mutating func setValue(_ refs: [Schematic.Ref], to value: String) {
		setValue(of: Set(refs.compactMap { ref in
			guard case let .symbol(index) = ref, schematic.symbols.indices.contains(index)
			else { return nil }
			return schematic.symbols[index].reference
		}), to: value)
	}

	mutating func setValue(_ refs: [Ref], to value: String) {
		setValue(of: Set(refs.compactMap { ref in
			guard case let .footprint(index) = ref, board.footprints.indices.contains(index)
			else { return nil }
			return board.footprints[index].reference
		}), to: value)
	}

	private mutating func setValue(of references: Set<String>, to value: String) {
		guard !references.isEmpty else { return }
		schematic.symbols.modifyEach { symbol in
			if references.contains(symbol.reference) { symbol.value = value }
		}
		board.footprints.modifyEach { footprint in
			if references.contains(footprint.reference) { footprint.value = value }
		}
	}
}

extension Binding where Value == Design {

	func value(of ref: Schematic.Ref) -> Binding<String?> { value(of: [ref]) }

	func value(of ref: Ref) -> Binding<String?> { value(of: [ref]) }

	func value(of refs: [Schematic.Ref]) -> Binding<String?> {
		Binding<String?>(
			get: { wrappedValue.values(of: refs).shared },
			set: { value in if let value { wrappedValue.setValue(refs, to: value) } }
		)
	}

	func value(of refs: [Ref]) -> Binding<String?> {
		Binding<String?>(
			get: { wrappedValue.values(of: refs).shared },
			set: { value in if let value { wrappedValue.setValue(refs, to: value) } }
		)
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
		schematic.symbols.append(Symbol(spec: spec, reference: reference, at: point))

		if let package = spec.footprint {
			let footprint = Footprint(spec: package, reference: reference, at: .zero)
			board.footprints.append(modifying(footprint) { footprint in
				footprint.at = board.parking(for: footprint)
				footprint.value = schematic.symbols[schematic.symbols.count - 1].value
			})
		}
		return .symbol(schematic.symbols.count - 1)
	}

	func symbol(of reference: String) -> Symbol? {
		schematic.symbols.first { $0.reference == reference }
	}

	func footprint(of reference: String) -> Footprint? {
		board.footprints.first { $0.reference == reference }
	}

	mutating func park(_ symbol: Symbol?, as reference: String) {
		guard let symbol else { return }
		schematic.symbols.append(modifying(symbol) { symbol in
			symbol.reference = reference
			symbol.at = schematic.parking(for: symbol)
		})
	}

	mutating func park(_ footprint: Footprint?, as reference: String) {
		guard let footprint else { return }
		board.footprints.append(modifying(footprint) { footprint in
			footprint.reference = reference
			footprint.at = board.parking(for: footprint)
		})
	}

	@discardableResult
	mutating func place(_ spec: Footprint.Spec, at point: Point) -> Ref {
		let reference = nextReference(like: spec.referencePrefix)
		board.footprints.append(Footprint(spec: spec, reference: reference, at: point))

		let symbol = Symbol(spec: spec.symbol, reference: reference, at: .zero)
		schematic.symbols.append(modifying(symbol) { symbol in
			symbol.at = schematic.parking(for: symbol)
			symbol.value = board.footprints[board.footprints.count - 1].value
		})
		return .footprint(board.footprints.count - 1)
	}
}

extension Design {

	func footprints(for selection: Set<Schematic.Ref>) -> Set<Ref> {
		let references = Set(selection.compactMap { ref -> String? in
			guard case let .symbol(index) = ref, schematic.symbols.indices.contains(index)
			else { return nil }
			return schematic.symbols[index].reference
		})
		return Set(
			board.footprints.indices
				.filter { references.contains(board.footprints[$0].reference) }
				.map(Ref.footprint)
		).union(selection.moduleIDs.map(Ref.module))
	}

	func symbols(for selection: Set<Ref>) -> Set<Schematic.Ref> {
		let references = Set(selection.compactMap { ref -> String? in
			guard case let .footprint(index) = ref, board.footprints.indices.contains(index)
			else { return nil }
			return board.footprints[index].reference
		})
		return Set(
			schematic.symbols.indices
				.filter { references.contains(schematic.symbols[$0].reference) }
				.map(Schematic.Ref.symbol)
		).union(selection.moduleIDs.map(Schematic.Ref.module))
	}
}
