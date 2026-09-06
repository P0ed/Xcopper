extension Schematic {

	func hitTest(at point: Point, tolerance: Int) -> Ref? {
		for (index, symbol) in symbols.enumerated().reversed() {
			let hit = symbol.placedPins.contains { pin in
				pin.figure.contains(point, tolerance: tolerance)
			}
			if hit || symbol.placedBody.outset(tolerance).contains(point) {
				return .symbol(index)
			}
		}
		for (index, label) in labels.enumerated().reversed()
		where label.bounds.outset(tolerance).contains(point) {
			return .label(index)
		}
		for (index, wire) in wires.enumerated().reversed()
		where wire.figure.contains(point, tolerance: tolerance) {
			return .wire(index)
		}
		return nil
	}

	func refs(at point: Point, tolerance: Int, whole: Bool = false) -> Set<Ref> {
		guard let hit = hitTest(at: point, tolerance: tolerance) else { return [] }
		guard whole, case let .wire(index) = hit else { return [hit] }
		return Set(routing().run(of: index).map(Ref.wire))
	}

	func isConnection(_ point: Point) -> Bool {
		routing().isTerminal(point, layer: 0) || wires.contains { touches(point, $0) }
	}

	func refs(in rect: Rect, whole: Bool = false) -> Set<Ref> {
		var result: Set<Ref> = []

		let covered = Set(wires.indices.filter { rect.contains(wires[$0].start) && rect.contains(wires[$0].end) })
		let route = routing()
		for index in covered where !whole || route.run(of: index).isSubset(of: covered) {
			result.insert(.wire(index))
		}
		for (index, symbol) in symbols.enumerated() where rect.contains(symbol.at) {
			result.insert(.symbol(index))
		}
		for (index, label) in labels.enumerated() where rect.contains(label.at) {
			result.insert(.label(index))
		}
		return result
	}

	func bounds(of refs: Set<Ref>) -> Rect? {
		Rect.union(refs.compactMap { ref in
			switch ref {
			case let .wire(index) where wires.indices.contains(index):
				Rect(from: wires[index].start, to: wires[index].end)
			case let .label(index) where labels.indices.contains(index):
				labels[index].bounds
			case let .symbol(index) where symbols.indices.contains(index):
				Rect.union(
					[symbols[index].placedBody]
						+ symbols[index].placedPins.map { pin in pin.figure.bounds }
				)
			default:
				nil
			}
		})
	}

	func snapTarget(near point: Point, radius: Int) -> Point? {
		var best: Point?
		var bestDistance = radius * radius + 1

		func consider(_ candidate: Point) {
			let distance = point.distanceSquared(to: candidate)
			guard distance < bestDistance else { return }
			bestDistance = distance
			best = candidate
		}

		for symbol in symbols {
			for pin in symbol.placedPins { consider(pin.at) }
		}
		for wire in wires {
			consider(wire.start)
			consider(wire.end)
			consider(nearest([wire.start, wire.end], to: point))
		}
		for label in labels { consider(label.at) }
		return best
	}
}

extension Schematic {

	func routing(moving refs: Set<Ref> = []) -> RouteGeometry<Wire> {
		var terminals: [RouteTerminal] = []
		for (index, symbol) in symbols.enumerated() {
			for pin in symbol.placedPins {
				terminals.append(RouteTerminal(
					figure: .round(pin.at, 0), layers: 0 ... 0, moving: refs.contains(.symbol(index))
				))
			}
		}
		for (index, label) in labels.enumerated() {
			terminals.append(RouteTerminal(
				figure: .round(label.at, 0), layers: 0 ... 0, moving: refs.contains(.label(index))
			))
		}
		return RouteGeometry(segments: wires, terminals: terminals, angles: .orthogonal)
	}

	@discardableResult
	mutating func move(_ refs: Set<Ref>, by delta: Point, grid: Nm = .mil(100)) -> Set<Ref>? {
		guard delta != .zero else { return refs }
		var route = routing(moving: refs)
		let points = Set(wires.flatMap { [$0.start, $0.end] }
			+ symbols.flatMap { $0.placedPins.map(\.at) } + labels.map(\.at))
		var pieces: [Wire] = []
		var selected: Set<Int> = []
		for (index, wire) in wires.enumerated() {
			let cuts = points.filter { touches($0, wire) }.sorted {
				wire.start.distanceSquared(to: $0) < wire.start.distanceSquared(to: $1)
			}
			for (start, end) in zip(cuts, cuts.dropFirst()) where start != end {
				if refs.contains(.wire(index)) { selected.insert(pieces.count) }
				pieces.append(Wire(start: start, end: end))
			}
		}
		route.segments = pieces
		guard let mapped = route.move(selected, by: delta, grid: grid) else { return nil }
		wires = route.segments
		for ref in refs {
			switch ref {
			case let .symbol(index) where symbols.indices.contains(index):
				symbols[index].at = symbols[index].at + delta
			case let .label(index) where labels.indices.contains(index):
				labels[index].at = labels[index].at + delta
			default: break
			}
		}
		return Set(refs.filter { if case .wire = $0 { false } else { true } })
			.union(selected.compactMap { mapped[$0].map(Ref.wire) })
	}

	mutating func remove(_ refs: Set<Ref>) {
		symbols.remove(at: refs.compactMap { if case let .symbol(i) = $0 { i } else { nil } })
		wires.remove(at: refs.compactMap { if case let .wire(i) = $0 { i } else { nil } })
		labels.remove(at: refs.compactMap { if case let .label(i) = $0 { i } else { nil } })
	}

	mutating func rotate(_ refs: Set<Ref>, clockwise: Bool, around center: Point? = nil) {
		guard let pivot = center ?? bounds(of: refs)?.center else { return }
		let rotation: Rotation = clockwise ? .r90 : .r270

		func spin(_ point: Point) -> Point { (point - pivot).rotated(rotation) + pivot }

		for ref in refs {
			switch ref {
			case let .wire(index) where wires.indices.contains(index):
				wires[index].start = spin(wires[index].start)
				wires[index].end = spin(wires[index].end)
			case let .label(index) where labels.indices.contains(index):
				labels[index].at = spin(labels[index].at)
			case let .symbol(index) where symbols.indices.contains(index):
				symbols[index].at = spin(symbols[index].at)
				symbols[index].rotation = clockwise
					? symbols[index].rotation.next
					: symbols[index].rotation.previous
			default:
				break
			}
		}
	}

	mutating func mirror(_ refs: Set<Ref>) {
		guard let pivot = bounds(of: refs)?.center else { return }

		func flip(_ point: Point) -> Point { Point(x: 2 * pivot.x - point.x, y: point.y) }

		for ref in refs {
			switch ref {
			case let .wire(index) where wires.indices.contains(index):
				wires[index].start = flip(wires[index].start)
				wires[index].end = flip(wires[index].end)
			case let .label(index) where labels.indices.contains(index):
				labels[index].at = flip(labels[index].at)
			case let .symbol(index) where symbols.indices.contains(index):
				symbols[index].at = flip(symbols[index].at)
				symbols[index].mirrored.toggle()
			default:
				break
			}
		}
	}

	mutating func duplicate(
		_ refs: Set<Ref>,
		by delta: Point,
		references used: Set<String> = []
	) -> Set<Ref> {
		var created: Set<Ref> = []
		for ref in refs.sorted(by: Ref.order) {
			switch ref {
			case let .wire(index) where wires.indices.contains(index):
				wires.append(modifying(wires[index]) { wire in
					wire.start = wire.start + delta
					wire.end = wire.end + delta
				})
				created.insert(.wire(wires.count - 1))
			case let .label(index) where labels.indices.contains(index):
				labels.append(modifying(labels[index]) { label in label.at = label.at + delta })
				created.insert(.label(labels.count - 1))
			case let .symbol(index) where symbols.indices.contains(index):
				symbols.append(modifying(symbols[index]) { symbol in
					symbol.at = symbol.at + delta
					symbol.reference = nextReference(like: symbol.reference, besides: used)
				})
				created.insert(.symbol(symbols.count - 1))
			default:
				break
			}
		}
		return created
	}

	func nextReference(like reference: String, besides used: Set<String> = []) -> String {
		Xcopper.nextReference(like: reference, used: Set(symbols.map(\.reference)).union(used))
	}
}

extension Schematic {

	func parking(for symbol: Symbol) -> Point {
		Xcopper.parking(symbol.placedExtent, in: bounds, clear: occupied)
	}

	private var occupied: [Rect] {
		symbols.map(\.placedExtent)
			+ wires.map { wire in Rect(from: wire.start, to: wire.end) }
			+ labels.map(\.bounds)
	}
}
