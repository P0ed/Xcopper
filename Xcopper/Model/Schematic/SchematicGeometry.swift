extension Board {

	func schematicHitTest(at point: Point, tolerance: Int) -> SchematicRef? {
		for (index, symbol) in symbols.enumerated().reversed() {
			let hit = symbol.placedPins.contains { pin in
				pin.figure.contains(point, tolerance: tolerance)
			}
			if hit || symbol.placedBody.outset(tolerance).contains(point) {
				return .symbol(index)
			}
		}
		for (index, wire) in wires.enumerated().reversed()
		where wire.figure.contains(point, tolerance: tolerance) {
			return .wire(index)
		}
		return nil
	}

	func schematicRefs(at point: Point, tolerance: Int, whole: Bool = false) -> Set<SchematicRef> {
		guard let hit = schematicHitTest(at: point, tolerance: tolerance) else { return [] }
		guard whole, case let .wire(index) = hit else { return [hit] }
		return Set(schematicRouting().run(of: index).map(SchematicRef.wire))
	}

	func isConnection(_ point: Point) -> Bool {
		schematicRouting().isTerminal(point, layer: 0) || wires.contains { touches(point, $0) }
	}

	func schematicRefs(in rect: Rect, whole: Bool = false) -> Set<SchematicRef> {
		var result: Set<SchematicRef> = []

		let covered = Set(wires.indices.filter { rect.contains(wires[$0].start) && rect.contains(wires[$0].end) })
		let route = schematicRouting()
		for index in covered where !whole || route.run(of: index).isSubset(of: covered) {
			result.insert(.wire(index))
		}
		for (index, symbol) in symbols.enumerated() where rect.contains(symbol.at) {
			result.insert(.symbol(index))
		}
		return result
	}

	func schematicBounds(of refs: Set<SchematicRef>) -> Rect? {
		Rect.union(refs.compactMap { ref in
			switch ref {
			case let .wire(index) where wires.indices.contains(index):
				Rect(from: wires[index].start, to: wires[index].end)
			case let .symbol(index) where footprints.indices.contains(index):
				Rect.union(
					[footprints[index].symbol.placedBody]
						+ footprints[index].symbol.placedPins.map { pin in pin.figure.bounds }
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
		return best
	}
}

extension Board {

	func schematicRouting(moving refs: Set<SchematicRef> = []) -> RouteGeometry<Wire> {
		var terminals: [RouteTerminal] = []
		for (index, symbol) in symbols.enumerated() {
			for pin in symbol.placedPins {
				terminals.append(RouteTerminal(
					figure: .round(pin.at, 0), layers: 0 ... 0, moving: refs.contains(.symbol(index))
				))
			}
		}
		return RouteGeometry(segments: wires, terminals: terminals, angles: .orthogonal)
	}

	@discardableResult
	mutating func moveSchematic(_ refs: Set<SchematicRef>, by delta: Point, grid: µm = 2_540) -> Set<SchematicRef>? {
		guard delta != .zero else { return refs }
		var route = schematicRouting(moving: refs)
		let points = Set(wires.flatMap { [$0.start, $0.end] }
			+ symbols.flatMap { $0.placedPins.map(\.at) })
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
			case let .symbol(index) where footprints.indices.contains(index):
				footprints[index].symbol.at = footprints[index].symbol.at + delta
			default: break
			}
		}
		return Set(refs.filter { if case .wire = $0 { false } else { true } })
			.union(selected.compactMap { mapped[$0].map(SchematicRef.wire) })
	}

	mutating func removeSchematic(_ refs: Set<SchematicRef>) {
		footprints.remove(at: refs.compactMap { if case let .symbol(i) = $0 { i } else { nil } })
		wires.remove(at: refs.compactMap { if case let .wire(i) = $0 { i } else { nil } })
	}

	mutating func rotateSchematic(_ refs: Set<SchematicRef>, clockwise: Bool, around center: Point? = nil) {
		guard let pivot = center ?? schematicBounds(of: refs)?.center else { return }
		let rotation: Rotation = clockwise ? .r90 : .r270

		func spin(_ point: Point) -> Point { (point - pivot).rotated(rotation) + pivot }

		for ref in refs {
			switch ref {
			case let .wire(index) where wires.indices.contains(index):
				wires[index].start = spin(wires[index].start)
				wires[index].end = spin(wires[index].end)
			case let .symbol(index) where footprints.indices.contains(index):
				footprints[index].symbol.at = spin(footprints[index].symbol.at)
				footprints[index].symbol.rotation = clockwise
					? footprints[index].symbol.rotation.next
					: footprints[index].symbol.rotation.previous
			default:
				break
			}
		}
	}

	mutating func mirrorSchematic(_ refs: Set<SchematicRef>) {
		guard let pivot = schematicBounds(of: refs)?.center else { return }

		func flip(_ point: Point) -> Point { Point(x: 2 * pivot.x - point.x, y: point.y) }

		for ref in refs {
			switch ref {
			case let .wire(index) where wires.indices.contains(index):
				wires[index].start = flip(wires[index].start)
				wires[index].end = flip(wires[index].end)
			case let .symbol(index) where footprints.indices.contains(index):
				footprints[index].symbol.at = flip(footprints[index].symbol.at)
				footprints[index].symbol.mirrored.toggle()
			default:
				break
			}
		}
	}

	mutating func duplicateSchematic(_ refs: Set<SchematicRef>, by delta: Point) -> Set<SchematicRef> {
		var created: Set<SchematicRef> = []
		for ref in refs.sorted(by: SchematicRef.order) {
			switch ref {
			case let .wire(index) where wires.indices.contains(index):
				wires.append(modifying(wires[index]) { wire in
					wire.start = wire.start + delta
					wire.end = wire.end + delta
				})
				created.insert(.wire(wires.count - 1))
			case let .symbol(index) where footprints.indices.contains(index):
				footprints.append(modifying(footprints[index]) { footprint in
					footprint.symbol.at = footprint.symbol.at + delta
				})
				created.insert(.symbol(footprints.count - 1))
			default:
				break
			}
		}
		return created
	}
}

extension Board {

	func parking(for symbol: Symbol) -> Point {
		parking(for: symbol, clear: schematicOccupied)
	}

	func parking(for symbol: Symbol, clear taken: [Rect]) -> Point {
		Xcopper.parking(symbol.placedExtent, in: sheetBounds, clear: taken)
	}

	var schematicOccupied: [Rect] {
		symbols.map(\.placedExtent)
			+ wires.map { wire in Rect(from: wire.start, to: wire.end) }
	}
}
