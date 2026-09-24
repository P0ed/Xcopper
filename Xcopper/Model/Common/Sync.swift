import SwiftUI

extension Binding where Value == Design {

	var synchronizingBoard: Binding<Design> {
		Binding(
			get: { wrappedValue },
			set: { next, transaction in
				var next = next
				let previous = wrappedValue
				if next.needsBoardSync(from: previous) {
					_ = next.updateBoardFromSchematic()
				}
				if next.board != previous.board || next.modules != previous.modules
					|| next.moduleCache != previous.moduleCache {
					next.inheritConnectedNets()
				}
				self.transaction(transaction).wrappedValue = next
			}
		)
	}
}

extension Design {

	func needsBoardSync(from previous: Design) -> Bool {
		board.symbols != previous.board.symbols
			|| board.footprints.map(\.reference) != previous.board.footprints.map(\.reference)
			|| board.wires != previous.board.wires
			|| moduleCache != previous.moduleCache
			|| !modules.elementsEqual(previous.modules) { one, other in
				one.id == other.id && one.reference == other.reference && one.filename == other.filename
					&& one.schematicAt == other.schematicAt
					&& one.schematicRotation == other.schematicRotation
					&& one.interface == other.interface
					&& one.netLabels == other.netLabels
			}
	}

	struct Report: Equatable {
		var assigned: Int = 0
		var created: [String] = []
		var missingPins: [String] = []

		var isClean: Bool {
			missingPins.isEmpty
		}
	}

	mutating func updateBoardFromSchematic() -> Report {
		if !modules.isEmpty {
			let projection = moduleProjection(syncNative: true, resolvingParameters: false)
			board.traces = Array(projection.design.board.traces.prefix(board.traces.count))
			board.vias = Array(projection.design.board.vias.prefix(board.vias.count))
			board.footprints = Array(projection.design.board.footprints.prefix(board.footprints.count))
			nets = projection.design.nets.filter { !projection.localNets.contains($0.id) }
			return projection.report
		}

		let netlist = Netlist(board)
		var report = Report()
		var usedNames = Set(netlist.groups.compactMap(\.name))
		var netNames = Dictionary(nets.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

		let groups = netlist.groups.map { ($0, $0.pinNames(in: board)) }
			.sorted { $0.1.lexicographicallyPrecedes($1.1) }
		for (group, pins) in groups {
			let nodes = group.nodes
				.sorted { ($0.symbol, $0.pin) < ($1.symbol, $1.pin) }

			guard nodes.count > 1 || group.name != nil, !nodes.isEmpty else { continue }

			let existingNames = nodes.flatMap { node -> [String] in
				let footprint = node.symbol
				let symbol = board.footprints[footprint].symbol
				let number = symbol.pins[node.pin].number
				return board.footprints[footprint].pads
					.filter { $0.name == number }
					.compactMap { $0.net.flatMap { id in netNames[id] } }
			}
			let existingName = existingNames.filter { $0.hasPrefix("N$") && !usedNames.contains($0) }.min()
			let name = group.name ?? existingName ?? unusedName("N$\(pins.joined(separator: "/"))", in: usedNames)
			usedNames.insert(name)
			let (id, created) = net(named: name)
			netNames[id] = name
			if created { report.created.append(name) }

			for node in nodes {
				let footprint = node.symbol
				let symbol = board.footprints[footprint].symbol
				let number = symbol.pins[node.pin].number
				let pads = board.footprints[footprint].pads.indices
					.filter { board.footprints[footprint].pads[$0].name == number }
				guard !pads.isEmpty else {
					report.missingPins.append("\(board.footprints[footprint].reference).\(number)")
					continue
				}
				for pad in pads { board.footprints[footprint].pads[pad].net = id }
				report.assigned += 1
			}
		}

		report.missingPins.sort()
		return report
	}
}

private func unusedName(_ base: String, in used: Set<String>) -> String {
	var name = base
	var suffix = 2
	while used.contains(name) {
		name = "\(base)/\(suffix)"
		suffix += 1
	}
	return name
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

	func footprints(at refs: [Ref]) -> [Footprint] {
		refs.compactMap { ref in
			guard case let .footprint(index) = ref, board.footprints.indices.contains(index)
			else { return nil }
			return board.footprints[index]
		}
	}

	func values(of refs: [SchematicRef]) -> [String] {
		refs.compactMap { ref in
			guard case let .symbol(index) = ref, board.footprints.indices.contains(index) else { return nil }
			return board.footprints[index].value
		}
	}

	func values(of refs: [Ref]) -> [String] { footprints(at: refs).map(\.value) }

	mutating func setValue(_ refs: [SchematicRef], to value: String) {
		setValue(Array(footprints(for: Set(refs))), to: value)
	}

	mutating func setValue(_ refs: [Ref], to value: String) {
		for case let .footprint(index) in refs where board.footprints.indices.contains(index) {
			board.footprints[index].value = value
		}
	}

	var usedReferences: Set<String> {
		Set(board.footprints.map(\.reference)).union(modules.map(\.reference))
	}

	func nextReference(like reference: String) -> String {
		Xcopper.nextReference(like: reference, used: usedReferences)
	}

	@discardableResult
	mutating func place(_ spec: Symbol.Spec, at point: Point) -> SchematicRef {
		var footprint = Footprint(symbol: spec, reference: nextReference(like: spec.referencePrefix), at: point)
		footprint.at = board.parking(for: footprint, clear: resolved.board.occupied)
		board.footprints.append(footprint)
		return .symbol(board.footprints.count - 1)
	}

	@discardableResult
	mutating func place(_ spec: Footprint.Spec, at point: Point) -> Ref {
		var footprint = Footprint(spec: spec, reference: nextReference(like: spec.referencePrefix), at: point)
		footprint.symbol.at = moduleProjection().sheet.parking(for: footprint.symbol)
		board.footprints.append(footprint)
		return .footprint(board.footprints.count - 1)
	}

	func footprints(for selection: Set<SchematicRef>) -> Set<Ref> {
		Set(selection.compactMap { ref in
			switch ref {
			case let .symbol(index) where board.footprints.indices.contains(index): .footprint(index)
			case let .module(id): .module(id)
			default: nil
			}
		})
	}

	func symbols(for selection: Set<Ref>) -> Set<SchematicRef> {
		Set(selection.compactMap { ref in
			switch ref {
			case let .footprint(index) where board.footprints.indices.contains(index): .symbol(index)
			case let .module(id): .module(id)
			default: nil
			}
		})
	}
}
