import Foundation

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

/// How far apart two points are, in millimeters
func length(from start: Pt, to end: Pt) -> Double {
	let dx = Double(end.x - start.x)
	let dy = Double(end.y - start.y)
	return (dx * dx + dy * dy).squareRoot().mm
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

/// Tangent of 22.5 degrees, scaled by 1000: where one routing direction gives
/// way to the next
let octantEdge = 414

/// The eight directions copper is routed along, counted round from east
let compass = [
	Pt(x: 1, y: 0), Pt(x: 1, y: 1), Pt(x: 0, y: 1), Pt(x: -1, y: 1),
	Pt(x: -1, y: 0), Pt(x: -1, y: -1), Pt(x: 0, y: -1), Pt(x: 1, y: -1),
]

func snapped45(from start: Pt, to end: Pt) -> Pt {
	let dx = end.x - start.x
	let dy = end.y - start.y
	guard dx != 0 || dy != 0 else { return end }

	let ax = abs(dx)
	let ay = abs(dy)

	if ay * 1000 <= ax * octantEdge { return Pt(x: end.x, y: start.y) }
	if ax * 1000 <= ay * octantEdge { return Pt(x: start.x, y: end.y) }

	let sx = dx < 0 ? -1 : 1
	let sy = dy < 0 ? -1 : 1
	let length = (ax + ay) / 2
	return Pt(x: start.x + sx * length, y: start.y + sy * length)
}

/// Nearest routing direction copper arriving along `heading` is allowed to
/// leave along, projected onto the way `snapped45` does. Straight on and the
/// two 45 degree turns are the whole of it: a route that would square the
/// corner is swung back to the nearer of the two.
func snapped45(from start: Pt, to end: Pt, after heading: Pt) -> Pt {
	let free = snapped45(from: start, to: end)
	guard let arriving = heading.octant, let wanted = (free - start).octant,
		!heading.bends(to: free - start)
	else { return free }

	// Swung back onto whichever of the two 45s lies nearer, counting round the
	// compass the short way
	let turn = (wanted - arriving + 8) % 8
	let direction = compass[(arriving + (turn <= 4 ? 1 : 7)) % 8]
	return start + direction * projection(of: end - start, onto: direction)
}

/// How far along `direction` an offset reaches, in whole steps of it, never
/// behind the start
private func projection(of offset: Pt, onto direction: Pt) -> Int {
	let along = offset.x * direction.x + offset.y * direction.y
	let step = direction.x != 0 && direction.y != 0 ? 2 : 1
	return max(0, along / step)
}

extension Pt {

	/// Whether an offset runs along one of the eight routing directions
	var isOctilinear: Bool { x == 0 || y == 0 || abs(x) == abs(y) }

	/// The eight way step an octilinear offset runs along, zero for no offset
	var heading: Pt { Pt(x: x.signum(), y: y.signum()) }

	/// The shortest whole step along the same line, which every whole point on
	/// that line is a number of. The heading for copper on the routing grid,
	/// and the nearest thing to one for copper drawn at a free angle.
	var step: Pt {
		let divisor = gcd(x, y)
		return divisor > 1 ? Pt(x: x / divisor, y: y / divisor) : self
	}

	/// Whether an offset runs the way `direction` does rather than back against
	/// it. Only worth asking of two that lie along the one line.
	func runsAlong(_ direction: Pt) -> Bool { x * direction.x + y * direction.y > 0 }

	/// Where the step an offset runs along sits on the compass, nil for no
	/// offset and for one drawn at a free angle
	var octant: Int? { isOctilinear ? compass.firstIndex(of: heading) : nil }

	/// How far, in eighths of a turn, copper running along self has to swing to
	/// leave along `next`: none carries straight on, one is the 45 degree bend
	/// copper is drawn with and two squares the corner. Nil where either side
	/// runs at a free angle, which is not this rule's to judge.
	func turn(to next: Pt) -> Int? {
		guard let from = octant, let to = next.octant else { return nil }
		let eighths = abs(to - from)
		return min(eighths, 8 - eighths)
	}

	/// Whether copper running along self may leave along `next`. A board turns
	/// 45 degrees at a time, so a right angle, and anything sharper, is a
	/// corner the copper is not allowed to make.
	func bends(to next: Pt) -> Bool { turn(to: next).map { $0 <= 1 } ?? true }
}

/// Greatest common divisor, what reduces an offset to the step it is made of
private func gcd(_ a: Int, _ b: Int) -> Int {
	var (a, b) = (abs(a), abs(b))
	while b != 0 { (a, b) = (b, a % b) }
	return a
}

/// Corner of the two legged 45 degree route from `start` to `end`. The bend
/// sits by `start`, the end that moved, unless the route already ran into
/// `end` along `heading` and the diagonal leg can keep that approach. Copper
/// running on from `start` along `leaving` outranks both: the leg order that
/// turns gently there wins, since a right angle is no corner to leave behind.
func bend(from start: Pt, to end: Pt, heading: Pt, leaving: Pt) -> Pt {
	let offset = end - start
	let diagonal = offset.heading
	let leg = diagonal * min(abs(offset.x), abs(offset.y))

	let (kept, other) = heading == diagonal ? (end - leg, start + leg) : (start + leg, end - leg)

	func turn(_ corner: Pt) -> Int { (-leaving).turn(to: corner - start) ?? 0 }
	let bend = turn(kept)
	return bend <= 1 || bend <= turn(other) ? kept : other
}

/// Where the line through `a` along `da` meets the one through `b` along `db`,
/// nil unless they meet at all, meet on a whole nanometer, and meet somewhere
/// a board coordinate reaches: two headings that all but agree cross a long
/// way past anything a drag was asking about.
func crossing(line a: Pt, _ da: Pt, line b: Pt, _ db: Pt) -> Pt? {
	let (da, db) = (da.step, db.step)
	let determinant = db.x * da.y - da.x * db.y
	guard determinant != 0 else { return nil }

	// How far along `da` the crossing lies. Counted in whole steps of it, since
	// the shortest step along a line reaches every whole point on it.
	let offset = b - a
	let along = db.x * offset.y - db.y * offset.x
	guard along.isMultiple(of: determinant) else { return nil }

	let steps = along / determinant
	let reach = max(abs(da.x), abs(da.y))
	guard abs(steps) <= Int(Nm.max) / reach else { return nil }
	return a + da * steps
}

/// Where the ray leaving `a` along `da` meets the one leaving `b` along `db`,
/// nil unless they cross ahead of both on a whole nanometer
func crossing(_ a: Pt, _ da: Pt, _ b: Pt, _ db: Pt) -> Pt? {
	guard let at = crossing(line: a, da, line: b, db),
		(at - a).runsAlong(da), (at - b).runsAlong(db)
	else { return nil }
	return at
}

/// Nearest orthogonal projection, the convention for schematic wires
func snapped90(from start: Pt, to end: Pt) -> Pt {
	let dx = end.x - start.x
	let dy = end.y - start.y
	return abs(dx) >= abs(dy) ? Pt(x: end.x, y: start.y) : Pt(x: start.x, y: end.y)
}

extension Board {

	/// Placed pads reaching `layer`. A through pad reaches every layer, so it
	/// turns up on both faces.
	func pads(on layer: Int) -> [Pad] {
		footprints.flatMap { footprint in
			footprint.placedPads.filter { pad in
				pad.isThrough || footprint.layer(of: pad, in: stack) == layer
			}
		}
	}

	/// Copper on `layer`, paired with the net it belongs to
	func figures(on layer: Int) -> [(Figure, Net.ID?)] {
		var result: [(Figure, Net.ID?)] = []

		for trace in traces where trace.layer == layer {
			result.append((.segment(trace.start, trace.end, trace.width), trace.net))
		}
		for via in vias where via.spans(layer) {
			result.append((.round(via.at, via.pad), via.net))
		}
		for pad in pads(on: layer) {
			result.append((pad.figure, pad.net))
		}
		return result
	}

	/// Copper on `layer` belonging to `refs`, what a selection lights up. A
	/// footprint brings its pads, so picking a part brightens the copper it
	/// stands on rather than the outline round it.
	func figures(on layer: Int, of refs: Set<Ref>) -> [Figure] {
		var result: [Figure] = []

		for case let .trace(index) in refs
		where traces.indices.contains(index) && traces[index].layer == layer {
			let trace = traces[index]
			result.append(.segment(trace.start, trace.end, trace.width))
		}
		for case let .via(index) in refs
		where vias.indices.contains(index) && vias[index].spans(layer) {
			result.append(.round(vias[index].at, vias[index].pad))
		}
		for case let .footprint(index) in refs where footprints.indices.contains(index) {
			let footprint = footprints[index]
			for pad in footprint.placedPads
			where pad.isThrough || footprint.layer(of: pad, in: stack) == layer {
				result.append(pad.figure)
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

	/// Everything one click picks up: the segment under the pointer, or, with
	/// `whole` on, the rest of the run it was drawn as part of, so a route
	/// selects, moves and deletes as the single object it was drawn as.
	func refs(at point: Pt, layer: Int, tolerance: Int, whole: Bool = false) -> Set<Ref> {
		guard let hit = hitTest(at: point, layer: layer, tolerance: tolerance) else { return [] }
		guard whole, case let .trace(index) = hit else { return [hit] }
		return Set(run(of: index).map(Ref.trace))
	}

	/// Everything a rubber band picks up. A segment comes along when the band
	/// holds both its ends; with `whole` on a run is one object, so a band
	/// covering part of one takes none of it.
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

	/// Segments chained end to end with `index` on its layer. The run stops
	/// where copper branches or lands on a pad or via, so it spans exactly what
	/// one routing gesture draws between two terminals.
	func run(of index: Int) -> Set<Int> {
		guard traces.indices.contains(index) else { return [] }

		var run: Set<Int> = [index]
		var pending = [index]

		while let current = pending.popLast() {
			for point in [traces[current].start, traces[current].end] {
				guard let next = continuation(of: current, at: point), run.insert(next).inserted
				else { continue }
				pending.append(next)
			}
		}
		return run
	}

	/// The one other segment meeting `index` at `point`, when the junction is a
	/// plain corner: two ends and no terminal
	func continuation(of index: Int, at point: Pt) -> Int? {
		let layer = traces[index].layer
		guard !isTerminal(point, layer: layer) else { return nil }

		var corner: Int?
		for (other, trace) in traces.enumerated()
		where other != index && trace.layer == layer
			&& (trace.start == point || trace.end == point) {
			guard corner == nil else { return nil }
			corner = other
		}
		return corner
	}

	/// The one heading copper leaves `point` along, passing over `ignoring`,
	/// when the junction is a corner a bend has to keep to. A pad or a via
	/// joins copper rather than bending it, and neither a branch nor copper
	/// drawn at a free angle has one heading, so none of them tie a route down.
	func heading(leaving point: Pt, layer: Int, ignoring skipped: Int? = nil) -> Pt? {
		guard !isTerminal(point, layer: layer) else { return nil }

		var heading: Pt?
		for (index, trace) in traces.enumerated()
		where index != skipped && trace.layer == layer
			&& (trace.start == point || trace.end == point) {
			let offset = (trace.start == point ? trace.end : trace.start) - point
			guard heading == nil, offset.isOctilinear, offset != .zero else { return nil }
			heading = offset.heading
		}
		return heading
	}

	/// Whether a pad or via lands on `point`, where a run ends
	func isTerminal(_ point: Pt, layer: Int) -> Bool {
		for via in vias
		where via.spans(layer) && Figure.round(via.at, via.pad).contains(point) {
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

	/// Where a route lands and is done: a pad, a via, or the end of copper
	/// already drawn on the layer
	func isConnection(_ point: Pt, layer: Int) -> Bool {
		isTerminal(point, layer: layer)
			|| traces.contains { trace in
				trace.layer == layer && (trace.start == point || trace.end == point)
			}
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

extension Figure {

	/// The outline as a closed loop of points, wound the way the layout draws
	/// it. Curves are cut into `arc` steps per quarter turn, which is what
	/// gives the 3D preview something flat to raise copper and packages over,
	/// and left to itself into as many steps as the curve is wide enough to
	/// show.
	func polygon(arc: Int? = nil) -> [Pt] {
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

/// How finely a curve this wide is cut, in steps per quarter turn. A side of
/// the ring a curve is drawn as falls a little inside the curve itself, and
/// holding that under about twenty microns is what settles this: a via's barrel
/// comes back with the twelve sides it has always had, and a panel jack's ring
/// with thirty two, which is as fine as anything is cut. Past that the sides
/// are shorter than anything reads and the model is better off carrying fewer
/// of them.
func fineness(across width: Int) -> Int {
	min(8, max(3, Int((3.0 * Double(width).mm.squareRoot()).rounded())))
}

/// A closed ring of points around `center`, wound like `Rect.corners`
func circle(at center: Pt, diameter: Int, arc: Int? = nil) -> [Pt] {
	let steps = max(3, (arc ?? fineness(across: diameter)) * 4)
	let radius = Double(diameter) / 2.0
	return (0 ..< steps).map { step in
		let angle = Double(step) / Double(steps) * 2.0 * .pi
		return Pt(
			x: center.x + Int((cos(angle) * radius).rounded()),
			y: center.y + Int((sin(angle) * radius).rounded())
		)
	}
}

/// A trace as a closed outline: the two sides of the run, with a half turn
/// round each end, the same shape the layout fills it with
func stadium(from start: Pt, to end: Pt, width: Int, arc: Int? = nil) -> [Pt] {
	let radius = Double(width) / 2.0
	let offset = end - start
	guard offset.x != 0 || offset.y != 0 else {
		return circle(at: start, diameter: width, arc: arc)
	}
	let heading = atan2(Double(offset.y), Double(offset.x))
	let steps = max(2, (arc ?? fineness(across: width)) * 2)

	var loop: [Pt] = []
	loop.reserveCapacity((steps + 1) * 2)
	for (center, base) in [(end, heading - .pi / 2.0), (start, heading + .pi / 2.0)] {
		for step in 0 ... steps {
			let angle = base + Double(step) / Double(steps) * .pi
			loop.append(Pt(
				x: center.x + Int((cos(angle) * radius).rounded()),
				y: center.y + Int((sin(angle) * radius).rounded())
			))
		}
	}
	return loop
}

// MARK: punching a face

/// What is left of a face once the drills reaching into it are punched through
/// it. A hole is drilled after the copper is laid, so no copper stands over
/// one: a pad is cut back to the rim of its own barrel, and so is a trace
/// running onto it or a ring overlapping the hole beside it.
///
/// A drill is taken out one edge at a time. What falls beyond an edge is
/// outside the drill and comes away as a piece of the face in its own right;
/// what falls behind every edge of it is inside the drill and is what the drill
/// takes away. Both cuts are made along a straight line, so a convex face comes
/// back in convex pieces and the next drill is punched through those in turn —
/// which is what makes the cutting exact however many holes reach into one
/// face, and however they overlap it and each other.
func punched(_ loop: [Pt], by drills: [[Pt]]) -> [[Pt]] {
	drills.reduce([loop]) { pieces, drill in
		pieces.flatMap { piece in punched(piece, by: drill) }
	}
}

/// Whether a convex loop holds another whole, which is what tells a drill the
/// face closes round — one the fab leaves as a hole through it — from a drill
/// that cuts into its edge and takes a piece of it away
func holds(_ outline: [Pt], _ loop: [Pt]) -> Bool {
	guard outline.count >= 3 else { return false }
	return loop.allSatisfy { point in
		outline.indices.allSatisfy { index in
			cross(outline[index], outline[(index + 1) % outline.count], point) > 0
		}
	}
}

private func punched(_ loop: [Pt], by drill: [Pt]) -> [[Pt]] {
	guard drill.count >= 3, loop.count >= 3 else { return [loop] }

	// A cut is made along the line an edge of the drill lies on, and a line
	// runs on for ever. So the face is cut down to the square the drill stands
	// in first: copper out there is nowhere near the hole and comes away whole,
	// rather than in as many slivers as the drill has edges.
	let (away, near) = cut(loop, to: reach(of: drill).corners)
	guard near.count >= 3 else { return [loop] }

	return away + cut(near, to: drill).outside
}

/// Cuts a loop to a convex one, edge by edge: the pieces of it lying outside,
/// and what is left of it inside. Every cut runs along a straight line, so each
/// piece is as convex as the loop it was cut from and the two sides of a cut
/// meet along it exactly.
private func cut(_ loop: [Pt], to convex: [Pt]) -> (outside: [[Pt]], inside: [Pt]) {
	var outside: [[Pt]] = []
	var inside = loop

	for index in convex.indices {
		let (from, to) = (convex[index], convex[(index + 1) % convex.count])
		let beyond = clipped(inside, by: from, to, keeping: false)
		if beyond.count >= 3 { outside.append(beyond) }

		inside = clipped(inside, by: from, to, keeping: true)
		// Nothing of the loop is left for the rest of the edges to cut
		guard inside.count >= 3 else { return (outside, []) }
	}
	return (outside, inside)
}

/// The square a loop stands in
private func reach(of loop: [Pt]) -> Rect {
	var lower = loop[0]
	var upper = loop[0]

	for point in loop.dropFirst() {
		lower = Pt(x: min(lower.x, point.x), y: min(lower.y, point.y))
		upper = Pt(x: max(upper.x, point.x), y: max(upper.y, point.y))
	}
	return Rect(from: lower, to: upper)
}

/// The part of a loop lying to one side of the line from `a` to `b`, cut where
/// the loop crosses it: the side the drill keeps its inside on, or the side
/// beyond it. A corner standing on the line belongs to both sides, so the two
/// parts a cut leaves meet along it exactly rather than with a gap between
/// them, and each is wound the way the loop it was cut from is.
private func clipped(_ loop: [Pt], by a: Pt, _ b: Pt, keeping inside: Bool) -> [Pt] {
	var kept: [Pt] = []
	kept.reserveCapacity(loop.count + 2)

	for index in loop.indices {
		let (from, to) = (loop[index], loop[(index + 1) % loop.count])
		let (here, there) = (cross(a, b, from), cross(a, b, to))

		if inside ? here >= 0 : here <= 0 { kept.append(from) }
		// A corner on the line is where the loop crosses it, and is already
		// kept by both sides; only an edge that steps clean over needs cutting
		if (here > 0 && there < 0) || (here < 0 && there > 0) {
			kept.append(meeting(from, to, crossing: a, b))
		}
	}
	return kept
}

/// Where the edge from `from` to `to` crosses the line from `a` to `b`, on the
/// nearest whole nanometer. Only asked of an edge that steps over the line, so
/// there is always somewhere it crosses.
private func meeting(_ from: Pt, _ to: Pt, crossing a: Pt, _ b: Pt) -> Pt {
	let here = Double(cross(a, b, from))
	let there = Double(cross(a, b, to))
	let along = here / (here - there)

	return Pt(
		x: from.x + Int((Double(to.x - from.x) * along).rounded()),
		y: from.y + Int((Double(to.y - from.y) * along).rounded())
	)
}

/// Twice the area of the triangle `abc`, positive where `c` lies to the left of
/// the line from `a` to `b`, which for a loop wound the way the layout draws
/// one is its inside
private func cross(_ a: Pt, _ b: Pt, _ c: Pt) -> Int {
	(b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
}
