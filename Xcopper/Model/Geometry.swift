/// Copper or clearance primitive, board coordinates
enum Figure: Hashable {
	case rect(Rect)
	case round(Pt, Nm)
	case segment(Pt, Pt, Nm)
}

extension Figure {

	func outset(_ amount: Int) -> Figure {
		switch self {
		case let .rect(rect): .rect(rect.outset(amount))
		case let .round(center, diameter): .round(center, Nm(clamping: Int(diameter) + amount * 2))
		case let .segment(start, end, width): .segment(start, end, Nm(clamping: Int(width) + amount * 2))
		}
	}

	var bounds: Rect {
		switch self {
		case let .rect(rect):
			rect
		case let .round(center, diameter):
			Rect(center: center, size: Size(width: Int(diameter), height: Int(diameter)))
		case let .segment(start, end, width):
			Rect(from: start, to: end).outset(Int(width) / 2)
		}
	}

	func contains(_ point: Pt, tolerance: Int = 0) -> Bool {
		switch self {
		case let .rect(rect):
			rect.outset(tolerance).contains(point)
		case let .round(center, diameter):
			point.isNear(center, within: Int(diameter) / 2 + tolerance)
		case let .segment(start, end, width):
			distance(from: point, to: start, end) <= Double(Int(width) / 2 + tolerance)
		}
	}
}

func distance(from point: Pt, to start: Pt, _ end: Pt) -> Double {
	let dx = Double(end.x - start.x)
	let dy = Double(end.y - start.y)
	let px = Double(point.x - start.x)
	let py = Double(point.y - start.y)
	let lengthSquared = dx * dx + dy * dy
	guard lengthSquared > 0 else { return (px * px + py * py).squareRoot() }
	let t = min(max((px * dx + py * dy) / lengthSquared, 0.0), 1.0)
	let ox = px - t * dx
	let oy = py - t * dy
	return (ox * ox + oy * oy).squareRoot()
}

/// Tangent of 22.5 degrees, scaled by 1000
let octant = 414

func snapped45(from start: Pt, to end: Pt) -> Pt {
	let dx = end.x - start.x
	let dy = end.y - start.y
	guard dx != 0 || dy != 0 else { return end }

	let ax = abs(dx)
	let ay = abs(dy)

	if ay * 1000 <= ax * octant { return Pt(x: end.x, y: start.y) }
	if ax * 1000 <= ay * octant { return Pt(x: start.x, y: end.y) }

	let sx = dx < 0 ? -1 : 1
	let sy = dy < 0 ? -1 : 1
	let length = (ax + ay) / 2
	return Pt(x: start.x + sx * length, y: start.y + sy * length)
}

extension Board {

	/// Copper on `layer`, paired with the net it belongs to
	func figures(on layer: Int) -> [(Figure, Net.ID?)] {
		var result: [(Figure, Net.ID?)] = []

		for trace in traces where trace.layer == layer {
			result.append((.segment(trace.start, trace.end, trace.width), trace.net))
		}
		for via in vias where via.spans(layer) {
			result.append((.round(via.at, via.pad), via.net))
		}
		for footprint in footprints {
			for pad in footprint.placedPads
			where pad.isThrough || footprint.layer(of: pad, in: stack) == layer {
				result.append((pad.figure, pad.net))
			}
		}
		return result
	}

	/// Everything on `layer` that a plane carrying `net` must keep clear of
	func clearances(on layer: Int, net: Net.ID?) -> [Figure] {
		var result = figures(on: layer)
			.filter { _, other in other != net }
			.map { figure, _ in figure.outset(Int(rules.clearance)) }

		for hole in holes {
			result.append(.round(hole.at, hole.diameter).outset(Int(rules.clearance)))
		}
		return result
	}

	/// Drill barrels punched on every layer
	var drills: [Figure] {
		vias.map { via in .round(via.at, via.drill) }
			+ holes.map { hole in .round(hole.at, hole.diameter) }
			+ footprints.flatMap { footprint in
				footprint.placedPads.filter(\.isThrough).map { pad in .round(pad.at, pad.drill) }
			}
	}
}

extension Pad {

	var figure: Figure {
		switch shape {
		case .rect:
			.rect(Rect(center: at, size: size))
		case .oval where size.width == size.height:
			.round(at, Nm(clamping: size.width))
		case .oval where size.width > size.height:
			.segment(
				Pt(x: at.x - (size.width - size.height) / 2, y: at.y),
				Pt(x: at.x + (size.width - size.height) / 2, y: at.y),
				Nm(clamping: size.height)
			)
		case .oval:
			.segment(
				Pt(x: at.x, y: at.y - (size.height - size.width) / 2),
				Pt(x: at.x, y: at.y + (size.height - size.width) / 2),
				Nm(clamping: size.width)
			)
		}
	}
}

extension Board {

	func hitTest(at point: Pt, layer: Int, tolerance: Int) -> Ref? {
		for (index, footprint) in footprints.enumerated().reversed() {
			let hit = footprint.placedPads.contains { pad in
				(pad.isThrough || footprint.layer(of: pad, in: stack) == layer)
					&& pad.figure.contains(point, tolerance: tolerance)
			}
			if hit || footprint.placedBody.outset(tolerance).contains(point) {
				return .footprint(index)
			}
		}
		for (index, via) in vias.enumerated().reversed()
		where Figure.round(via.at, via.pad).contains(point, tolerance: tolerance) {
			return .via(index)
		}
		for (index, hole) in holes.enumerated().reversed()
		where Figure.round(hole.at, hole.diameter).contains(point, tolerance: tolerance) {
			return .hole(index)
		}
		for (index, trace) in traces.enumerated().reversed()
		where trace.layer == layer
			&& Figure.segment(trace.start, trace.end, trace.width).contains(point, tolerance: tolerance) {
			return .trace(index)
		}
		return nil
	}

	func refs(in rect: Rect, layer: Int) -> Set<Ref> {
		var result: Set<Ref> = []

		for (index, trace) in traces.enumerated()
		where trace.layer == layer && rect.contains(trace.start) && rect.contains(trace.end) {
			result.insert(.trace(index))
		}
		for (index, via) in vias.enumerated() where rect.contains(via.at) {
			result.insert(.via(index))
		}
		for (index, hole) in holes.enumerated() where rect.contains(hole.at) {
			result.insert(.hole(index))
		}
		for (index, footprint) in footprints.enumerated() where rect.contains(footprint.at) {
			result.insert(.footprint(index))
		}
		return result
	}

	func bounds(of refs: Set<Ref>) -> Rect? {
		Rect.union(refs.compactMap { ref in
			switch ref {
			case let .trace(index) where traces.indices.contains(index):
				Rect(from: traces[index].start, to: traces[index].end)
			case let .via(index) where vias.indices.contains(index):
				Figure.round(vias[index].at, vias[index].pad).bounds
			case let .hole(index) where holes.indices.contains(index):
				Figure.round(holes[index].at, holes[index].diameter).bounds
			case let .footprint(index) where footprints.indices.contains(index):
				Rect.union(
					[footprints[index].placedBody]
						+ footprints[index].placedPads.map { pad in pad.figure.bounds }
				)
			default:
				nil
			}
		})
	}

	/// Pad, via or trace endpoint worth snapping a route to
	func snapTarget(near point: Pt, layer: Int, radius: Int) -> (Pt, Net.ID?)? {
		var best: (Pt, Net.ID?)?
		var bestDistance = radius * radius + 1

		func consider(_ candidate: Pt, _ net: Net.ID?) {
			let distance = point.distanceSquared(to: candidate)
			guard distance < bestDistance else { return }
			bestDistance = distance
			best = (candidate, net)
		}

		for footprint in footprints {
			for pad in footprint.placedPads
			where pad.isThrough || footprint.layer(of: pad, in: stack) == layer {
				consider(pad.at, pad.net)
			}
		}
		for via in vias where via.spans(layer) {
			consider(via.at, via.net)
		}
		for trace in traces where trace.layer == layer {
			consider(trace.start, trace.net)
			consider(trace.end, trace.net)
		}
		return best
	}
}
