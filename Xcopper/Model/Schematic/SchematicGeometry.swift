extension Schematic {

	func hitTest(at point: Pt, tolerance: Int) -> Ref? {
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

	func refs(in rect: Rect) -> Set<Ref> {
		var result: Set<Ref> = []

		for (index, wire) in wires.enumerated()
		where rect.contains(wire.start) && rect.contains(wire.end) {
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

	func snapTarget(near point: Pt, radius: Int) -> Pt? {
		var best: Pt?
		var bestDistance = radius * radius + 1

		func consider(_ candidate: Pt) {
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
		}
		return best
	}
}

extension Schematic {

	mutating func move(_ refs: Set<Ref>, by delta: Pt) {
		for ref in refs {
			switch ref {
			case let .wire(index) where wires.indices.contains(index):
				wires[index].start = wires[index].start + delta
				wires[index].end = wires[index].end + delta
			case let .symbol(index) where symbols.indices.contains(index):
				symbols[index].at = symbols[index].at + delta
			case let .label(index) where labels.indices.contains(index):
				labels[index].at = labels[index].at + delta
			default:
				break
			}
		}
	}

	mutating func remove(_ refs: Set<Ref>) {
		symbols.remove(at: refs.compactMap { if case let .symbol(i) = $0 { i } else { nil } })
		wires.remove(at: refs.compactMap { if case let .wire(i) = $0 { i } else { nil } })
		labels.remove(at: refs.compactMap { if case let .label(i) = $0 { i } else { nil } })
	}

	mutating func rotate(_ refs: Set<Ref>, clockwise: Bool) {
		guard let pivot = bounds(of: refs)?.center else { return }
		let rotation: Rotation = clockwise ? .r90 : .r270

		func spin(_ point: Pt) -> Pt { (point - pivot).rotated(rotation) + pivot }

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

		func flip(_ point: Pt) -> Pt { Pt(x: 2 * pivot.x - point.x, y: point.y) }

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
		by delta: Pt,
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

	func parking(for symbol: Symbol) -> Pt {
		Xcopper.parking(symbol.placedExtent, in: bounds, clear: occupied)
	}

	private var occupied: [Rect] {
		symbols.map(\.placedExtent)
			+ wires.map { wire in Rect(from: wire.start, to: wire.end) }
			+ labels.map(\.bounds)
	}
}
