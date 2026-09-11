import Foundation

enum Figure: Hashable {
	case rect(Rect)
	case round(Point, µm)
	case segment(Point, Point, µm)
}

extension Figure {

	func outset(_ amount: µm) -> Figure {
		switch self {
		case let .rect(rect): .rect(rect.outset(amount))
		case let .round(center, diameter): .round(center, µm(clamping: diameter + amount * 2))
		case let .segment(start, end, width): .segment(start, end, µm(clamping: width + amount * 2))
		}
	}

	var bounds: Rect {
		switch self {
		case let .rect(rect):
			rect
		case let .round(center, diameter):
			Rect(center: center, size: Size(width: diameter, height: diameter))
		case let .segment(start, end, width):
			Rect(from: start, to: end).outset(width / 2)
		}
	}

	func contains(_ point: Point, tolerance: Int = 0) -> Bool {
		switch self {
		case let .rect(rect):
			rect.outset(tolerance).contains(point)
		case let .round(center, diameter):
			point.isNear(center, within: diameter / 2 + tolerance)
		case let .segment(start, end, width):
			distance(from: point, to: start, end) <= Double(Int(width) / 2 + tolerance)
		}
	}
}

func length(from start: Point, to end: Point) -> Double {
	let dx = Double(end.x - start.x)
	let dy = Double(end.y - start.y)
	return (dx * dx + dy * dy).squareRoot() / 1_000
}

func distance(from point: Point, to start: Point, _ end: Point) -> Double {
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

private let parkingPitch = 2_540

func parking(_ extent: Rect, in bounds: Rect, clear taken: [Rect]) -> Point {
	var fallback: Point?
	var y = bounds.minY + parkingPitch

	while y <= bounds.maxY {
		var x = bounds.minX + parkingPitch
		while x <= bounds.maxX {
			let at = Point(x: x, y: y)
			let placed = Rect(origin: extent.origin + at, size: extent.size)
			if bounds.contains(placed.origin), bounds.contains(Point(x: placed.maxX, y: placed.maxY)) {
				if fallback == nil { fallback = at }
				let room = placed.outset(parkingPitch / 2)
				if !taken.contains(where: room.intersects) { return at }
			}
			x += parkingPitch
		}
		y += parkingPitch
	}
	return fallback ?? bounds.center
}

private let octantEdge = 414

private let compass = [
	Point(x: 1, y: 0), Point(x: 1, y: 1), Point(x: 0, y: 1), Point(x: -1, y: 1),
	Point(x: -1, y: 0), Point(x: -1, y: -1), Point(x: 0, y: -1), Point(x: 1, y: -1),
]

func snapped45(from start: Point, to end: Point) -> Point {
	let dx = end.x - start.x
	let dy = end.y - start.y
	guard dx != 0 || dy != 0 else { return end }

	let ax = abs(dx)
	let ay = abs(dy)

	if ay * 1000 <= ax * octantEdge { return Point(x: end.x, y: start.y) }
	if ax * 1000 <= ay * octantEdge { return Point(x: start.x, y: end.y) }

	let sx = dx < 0 ? -1 : 1
	let sy = dy < 0 ? -1 : 1
	let length = (ax + ay) / 2
	return Point(x: start.x + sx * length, y: start.y + sy * length)
}

func snapped45(from start: Point, to end: Point, after heading: Point) -> Point {
	let free = snapped45(from: start, to: end)
	guard let arriving = heading.octant, let wanted = (free - start).octant,
		!heading.bends(to: free - start)
	else { return free }

	let turn = (wanted - arriving + 8) % 8
	let direction = compass[(arriving + (turn <= 4 ? 1 : 7)) % 8]
	return start + direction * projection(of: end - start, onto: direction)
}

private func projection(of offset: Point, onto direction: Point) -> Int {
	let along = offset.x * direction.x + offset.y * direction.y
	let step = direction.x != 0 && direction.y != 0 ? 2 : 1
	return max(0, along / step)
}

extension Point {

	var isOctilinear: Bool { x == 0 || y == 0 || abs(x) == abs(y) }

	var heading: Point { Point(x: x.signum(), y: y.signum()) }

	var step: Point {
		let divisor = gcd(x, y)
		return divisor > 1 ? Point(x: x / divisor, y: y / divisor) : self
	}

	func runsAlong(_ direction: Point) -> Bool { x * direction.x + y * direction.y > 0 }

	var octant: Int? { isOctilinear ? compass.firstIndex(of: heading) : nil }

	func turn(to next: Point) -> Int? {
		guard let from = octant, let to = next.octant else { return nil }
		let eighths = abs(to - from)
		return min(eighths, 8 - eighths)
	}

	func bends(to next: Point) -> Bool { turn(to: next).map { $0 <= 1 } ?? true }
}

private func gcd(_ a: Int, _ b: Int) -> Int {
	var (a, b) = (abs(a), abs(b))
	while b != 0 { (a, b) = (b, a % b) }
	return a
}

func bend(from start: Point, to end: Point, heading: Point, leaving: Point) -> Point {
	let offset = end - start
	let diagonal = offset.heading
	let leg = diagonal * min(abs(offset.x), abs(offset.y))

	let (kept, other) = heading == diagonal ? (end - leg, start + leg) : (start + leg, end - leg)

	func turn(_ corner: Point) -> Int { (-leaving).turn(to: corner - start) ?? 0 }
	let bend = turn(kept)
	return bend <= 1 || bend <= turn(other) ? kept : other
}

func crossing(line a: Point, _ da: Point, line b: Point, _ db: Point) -> Point? {
	let (da, db) = (da.step, db.step)
	let determinant = db.x * da.y - da.x * db.y
	guard determinant != 0 else { return nil }

	let offset = b - a
	let along = db.x * offset.y - db.y * offset.x
	guard along.isMultiple(of: determinant) else { return nil }

	let steps = along / determinant
	let reach = max(abs(da.x), abs(da.y))
	guard abs(steps) <= Int(µm.max) / reach else { return nil }
	return a + da * steps
}

func crossing(_ a: Point, _ da: Point, _ b: Point, _ db: Point) -> Point? {
	guard let at = crossing(line: a, da, line: b, db),
		(at - a).runsAlong(da), (at - b).runsAlong(db)
	else { return nil }
	return at
}

func snapped90(from start: Point, to end: Point) -> Point {
	let dx = end.x - start.x
	let dy = end.y - start.y
	return abs(dx) >= abs(dy) ? Point(x: end.x, y: start.y) : Point(x: start.x, y: end.y)
}

func snapped90(from start: Point, to end: Point, after heading: Point) -> Point {
	let free = snapped90(from: start, to: end)
	guard !RoutingAngles.orthogonal.bends(heading, to: free - start) else { return free }
	return heading.x != 0 ? Point(x: start.x, y: end.y) : Point(x: end.x, y: start.y)
}

extension Board {

	func pads(on layer: Int) -> [Pad] {
		footprints.flatMap { footprint in
			footprint.placedPads.filter { pad in
				pad.isThrough || footprint.layer(of: pad, in: stack) == layer
			}
		}
	}

	func figures(on layer: Int) -> [(Figure, Net.ID?)] {
		var result: [(Figure, Net.ID?)] = []

		for trace in traces where trace.layer == layer {
			result.append((.segment(trace.start, trace.end, trace.width), trace.net))
		}
		for via in vias where stack.contains(layer) {
			result.append((.round(via.at, rules.viaPad), via.net))
		}
		for pad in pads(on: layer) {
			result.append((pad.figure, pad.net))
		}
		for footprint in footprints {
			for trace in footprint.copper(in: stack) where trace.layer == layer {
				result.append((.segment(trace.start, trace.end, trace.width), trace.net))
			}
		}
		return result
	}

	func figures(on layer: Int, of refs: Set<Ref>) -> [Figure] {
		var result: [Figure] = []

		for case let .trace(index) in refs
		where traces.indices.contains(index) && traces[index].layer == layer {
			let trace = traces[index]
			result.append(.segment(trace.start, trace.end, trace.width))
		}
		for case let .via(index) in refs
		where vias.indices.contains(index) && stack.contains(layer) {
			result.append(.round(vias[index].at, rules.viaPad))
		}
		for case let .footprint(index) in refs where footprints.indices.contains(index) {
			let footprint = footprints[index]
			for trace in footprint.copper(in: stack) where trace.layer == layer {
				result.append(.segment(trace.start, trace.end, trace.width))
			}
			for pad in footprint.placedPads
			where pad.isThrough || footprint.layer(of: pad, in: stack) == layer {
				result.append(pad.figure)
			}
		}
		for ref in refs {
			guard case let .pad(index, _) = ref, !refs.contains(.footprint(index)),
				let (footprint, pad) = placedPad(ref),
				pad.isThrough || footprint.layer(of: pad, in: stack) == layer
			else { continue }
			result.append(pad.figure)
		}
		return result
	}

	func clearances(on layer: Int, net: Net.ID?) -> [Figure] {
		var result = figures(on: layer)
			.filter { _, other in other != net }
			.map { figure, _ in figure.outset(Int(rules.clearance)) }

		for hole in holes {
			result.append(.round(hole.at, hole.diameter).outset(Int(rules.clearance)))
		}
		return result
	}

	var drills: [Figure] {
		vias.map { via in .round(via.at, rules.viaDrill) }
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
			.round(at, µm(clamping: size.width))
		case .oval where size.width > size.height:
			.segment(
				Point(x: at.x - (size.width - size.height) / 2, y: at.y),
				Point(x: at.x + (size.width - size.height) / 2, y: at.y),
				µm(clamping: size.height)
			)
		case .oval:
			.segment(
				Point(x: at.x, y: at.y - (size.height - size.width) / 2),
				Point(x: at.x, y: at.y + (size.height - size.width) / 2),
				µm(clamping: size.width)
			)
		}
	}
}

extension Board {

	func hitTest(at point: Point, layer: Int, tolerance: Int, selection: Set<Ref> = []) -> Ref? {
		for (index, trace) in traces.enumerated().reversed()
		where trace.layer == layer
			&& Figure.segment(trace.start, trace.end, trace.width).contains(point, tolerance: tolerance) {
			return .trace(index)
		}
		for (index, via) in vias.enumerated().reversed()
		where Figure.round(via.at, rules.viaPad).contains(point, tolerance: tolerance) {
			return .via(index)
		}
		for (index, hole) in holes.enumerated().reversed()
		where Figure.round(hole.at, hole.diameter).contains(point, tolerance: tolerance) {
			return .hole(index)
		}
		for (index, footprint) in footprints.enumerated().reversed() where selection.contains(.footprint(index)) {
			for (padIndex, pad) in footprint.placedPads.enumerated().reversed()
			where (pad.isThrough || footprint.layer(of: pad, in: stack) == layer)
				&& pad.figure.contains(point, tolerance: tolerance) {
				return .pad(index, padIndex)
			}
		}
		for (index, footprint) in footprints.enumerated().reversed() {
			let hit = footprint.placedPads.contains { pad in
				(pad.isThrough || footprint.layer(of: pad, in: stack) == layer)
					&& pad.figure.contains(point, tolerance: tolerance)
			}
			if hit || footprint.placedBody.outset(tolerance).contains(point) {
				return .footprint(index)
			}
		}
		return nil
	}

	func refs(at point: Point, layer: Int, tolerance: Int, whole: Bool = false, selection: Set<Ref> = []) -> Set<Ref> {
		guard let hit = hitTest(at: point, layer: layer, tolerance: tolerance, selection: selection) else { return [] }
		guard whole, case let .trace(index) = hit else { return [hit] }
		return Set(run(of: index).map(Ref.trace))
	}

	func refs(in rect: Rect, layer: Int, whole: Bool = false) -> Set<Ref> {
		var result: Set<Ref> = []

		var covered: Set<Int> = []
		for (index, trace) in traces.enumerated()
		where trace.layer == layer && rect.contains(trace.start) && rect.contains(trace.end) {
			covered.insert(index)
		}
		for index in covered where !whole || run(of: index).isSubset(of: covered) {
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
				Figure.round(vias[index].at, rules.viaPad).bounds
			case let .hole(index) where holes.indices.contains(index):
				Figure.round(holes[index].at, holes[index].diameter).bounds
			case let .footprint(index) where footprints.indices.contains(index):
				footprints[index].placedExtent
			case .pad:
				placedPad(ref)?.pad.figure.bounds
			default:
				nil
			}
		})
	}

	func run(of index: Int) -> Set<Int> { routing().run(of: index) }

	func continuation(of index: Int, at point: Point) -> Int? { routing().continuation(of: index, at: point) }

	func heading(leaving point: Point, layer: Int, ignoring skipped: Int? = nil) -> Point? {
		routing().heading(leaving: point, layer: layer, ignoring: skipped)
	}

	func isTerminal(_ point: Point, layer: Int) -> Bool {
		for footprint in footprints {
			for trace in footprint.copper(in: stack)
			where trace.layer == layer && Figure.segment(trace.start, trace.end, trace.width).contains(point) {
				return true
			}
		}
		for via in vias
		where stack.contains(layer) && Figure.round(via.at, rules.viaPad).contains(point) {
			return true
		}
		for footprint in footprints {
			for pad in footprint.placedPads
			where (pad.isThrough || footprint.layer(of: pad, in: stack) == layer)
				&& pad.figure.contains(point) {
				return true
			}
		}
		return false
	}

	func isConnection(_ point: Point, layer: Int) -> Bool {
		isTerminal(point, layer: layer)
			|| traces.contains { trace in
				trace.layer == layer && (trace.start == point || trace.end == point)
			}
	}

	func snapTarget(near point: Point, layer: Int, radius: Int) -> (Point, Net.ID?)? {
		var best: (Point, Net.ID?)?
		var bestDistance = radius * radius + 1

		func consider(_ candidate: Point, _ net: Net.ID?) {
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
		for via in vias where stack.contains(layer) {
			consider(via.at, via.net)
		}
		for trace in traces where trace.layer == layer {
			consider(trace.start, trace.net)
			consider(trace.end, trace.net)
		}
		return best
	}
}

extension Figure {

	func polygon(arc: Int? = nil) -> [Point] {
		switch self {
		case let .rect(rect):
			rect.corners
		case let .round(center, diameter):
			circle(at: center, diameter: Int(diameter), arc: arc)
		case let .segment(start, end, width):
			stadium(from: start, to: end, width: Int(width), arc: arc)
		}
	}
}

func fineness(across width: Int) -> Int {
	min(8, max(3, Int((3.0 * Double.mm(width).squareRoot()).rounded())))
}

func circle(at center: Point, diameter: Int, arc: Int? = nil) -> [Point] {
	let steps = max(3, (arc ?? fineness(across: diameter)) * 4)
	let radius = Double(diameter) / 2.0
	return (0 ..< steps).map { step in
		let angle = Double(step) / Double(steps) * 2.0 * .pi
		return Point(
			x: center.x + Int((cos(angle) * radius).rounded()),
			y: center.y + Int((sin(angle) * radius).rounded())
		)
	}
}

func stadium(from start: Point, to end: Point, width: Int, arc: Int? = nil) -> [Point] {
	let radius = Double(width) / 2.0
	let offset = end - start
	guard offset.x != 0 || offset.y != 0 else {
		return circle(at: start, diameter: width, arc: arc)
	}
	let heading = atan2(Double(offset.y), Double(offset.x))
	let steps = max(2, (arc ?? fineness(across: width)) * 2)

	var loop: [Point] = []
	loop.reserveCapacity((steps + 1) * 2)
	for (center, base) in [(end, heading - .pi / 2.0), (start, heading + .pi / 2.0)] {
		for step in 0 ... steps {
			let angle = base + Double(step) / Double(steps) * .pi
			loop.append(Point(
				x: center.x + Int((cos(angle) * radius).rounded()),
				y: center.y + Int((sin(angle) * radius).rounded())
			))
		}
	}
	return loop
}

extension Figure {

	var core: [Point] {
		switch self {
		case let .rect(rect): rect.corners
		case let .round(center, _): [center]
		case let .segment(start, end, _): [start, end]
		}
	}

	var radius: Int {
		switch self {
		case .rect: 0
		case let .round(_, diameter): Int(diameter) / 2
		case let .segment(_, _, width): Int(width) / 2
		}
	}
}

func gap(_ a: Figure, _ b: Figure) -> Double {
	max(0.0, gap(a.core, b.core) - Double(a.radius + b.radius))
}

func gap(_ a: [Point], _ b: [Point]) -> Double {
	guard let here = a.first, let there = b.first else { return .infinity }
	guard !covers(a, there), !covers(b, here) else { return 0.0 }

	var least = Double.infinity
	for edge in edges(a) {
		for other in edges(b) {
			least = min(least, gap(edge, other))
		}
	}
	return least
}

func nearest(_ loop: [Point], to point: Point) -> Point {
	guard !covers(loop, point) else { return point }

	var best = point
	var least = Int.max
	for (from, to) in edges(loop) {
		let candidate = nearest(from: from, to: to, near: point)
		let distance = point.distanceSquared(to: candidate)
		guard distance < least else { continue }
		least = distance
		best = candidate
	}
	return best
}

func meeting(_ a: Figure, _ b: Figure) -> Point {
	let near = nearest(a.core, to: b.bounds.center)
	let far = nearest(b.core, to: near)
	let back = nearest(a.core, to: far)
	return Point(x: (back.x + far.x) / 2, y: (back.y + far.y) / 2)
}

private func gap(_ a: (Point, Point), _ b: (Point, Point)) -> Double {
	guard !crosses(a, b) else { return 0.0 }
	return min(
		min(distance(from: a.0, to: b.0, b.1), distance(from: a.1, to: b.0, b.1)),
		min(distance(from: b.0, to: a.0, a.1), distance(from: b.1, to: a.0, a.1))
	)
}

private func crosses(_ a: (Point, Point), _ b: (Point, Point)) -> Bool {
	func straddles(_ from: Point, _ to: Point, _ first: Point, _ second: Point) -> Bool {
		let here = cross(from, to, first)
		let there = cross(from, to, second)
		return (here > 0 && there < 0) || (here < 0 && there > 0)
	}
	return straddles(a.0, a.1, b.0, b.1) && straddles(b.0, b.1, a.0, a.1)
}

private func covers(_ loop: [Point], _ point: Point) -> Bool {
	guard loop.count >= 3 else { return false }

	var enclosed = false
	for index in loop.indices {
		let side = cross(loop[index], loop[(index + 1) % loop.count], point)
		guard side >= 0 else { return false }
		enclosed = enclosed || side > 0
	}
	return enclosed
}

private func edges(_ loop: [Point]) -> [(Point, Point)] {
	switch loop.count {
	case 0: []
	case 1: [(loop[0], loop[0])]
	case 2: [(loop[0], loop[1])]
	default: loop.indices.map { index in (loop[index], loop[(index + 1) % loop.count]) }
	}
}

private func nearest(from start: Point, to end: Point, near point: Point) -> Point {
	let dx = Double(end.x - start.x)
	let dy = Double(end.y - start.y)
	let lengthSquared = dx * dx + dy * dy
	guard lengthSquared > 0.0 else { return start }

	let along = Double(point.x - start.x) * dx + Double(point.y - start.y) * dy
	let t = min(max(along / lengthSquared, 0.0), 1.0)
	return Point(
		x: start.x + Int((dx * t).rounded()),
		y: start.y + Int((dy * t).rounded())
	)
}

func punched(_ loop: [Point], by drills: [[Point]]) -> [[Point]] {
	drills.reduce([loop]) { pieces, drill in
		pieces.flatMap { piece in punched(piece, by: drill) }
	}
}

func holds(_ outline: [Point], _ loop: [Point]) -> Bool {
	guard outline.count >= 3 else { return false }
	return loop.allSatisfy { point in
		outline.indices.allSatisfy { index in
			cross(outline[index], outline[(index + 1) % outline.count], point) > 0
		}
	}
}

private func punched(_ loop: [Point], by drill: [Point]) -> [[Point]] {
	guard drill.count >= 3, loop.count >= 3 else { return [loop] }

	let (away, near) = cut(loop, to: reach(of: drill).corners)
	guard near.count >= 3 else { return [loop] }

	return away + cut(near, to: drill).outside
}

private func cut(_ loop: [Point], to convex: [Point]) -> (outside: [[Point]], inside: [Point]) {
	var outside: [[Point]] = []
	var inside = loop

	for index in convex.indices {
		let (from, to) = (convex[index], convex[(index + 1) % convex.count])
		let beyond = clipped(inside, by: from, to, keeping: false)
		if beyond.count >= 3 { outside.append(beyond) }

		inside = clipped(inside, by: from, to, keeping: true)
		guard inside.count >= 3 else { return (outside, []) }
	}
	return (outside, inside)
}

private func reach(of loop: [Point]) -> Rect {
	var lower = loop[0]
	var upper = loop[0]

	for point in loop.dropFirst() {
		lower = Point(x: min(lower.x, point.x), y: min(lower.y, point.y))
		upper = Point(x: max(upper.x, point.x), y: max(upper.y, point.y))
	}
	return Rect(from: lower, to: upper)
}

private func clipped(_ loop: [Point], by a: Point, _ b: Point, keeping inside: Bool) -> [Point] {
	var kept: [Point] = []
	kept.reserveCapacity(loop.count + 2)

	for index in loop.indices {
		let (from, to) = (loop[index], loop[(index + 1) % loop.count])
		let (here, there) = (cross(a, b, from), cross(a, b, to))

		if inside ? here >= 0 : here <= 0 { kept.append(from) }
		if (here > 0 && there < 0) || (here < 0 && there > 0) {
			kept.append(meeting(from, to, crossing: a, b))
		}
	}
	return kept
}

private func meeting(_ from: Point, _ to: Point, crossing a: Point, _ b: Point) -> Point {
	let here = Double(cross(a, b, from))
	let there = Double(cross(a, b, to))
	let along = here / (here - there)

	return Point(
		x: from.x + Int((Double(to.x - from.x) * along).rounded()),
		y: from.y + Int((Double(to.y - from.y) * along).rounded())
	)
}

private func cross(_ a: Point, _ b: Point, _ c: Point) -> Int {
	(b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
}
