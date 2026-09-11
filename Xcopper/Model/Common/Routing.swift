struct RouteEnd: Hashable {
	var segment: Int
	var isStart: Bool

	var other: RouteEnd { RouteEnd(segment: segment, isStart: !isStart) }

	static func order(_ lhs: RouteEnd, _ rhs: RouteEnd) -> Bool {
		(lhs.segment, lhs.isStart ? 0 : 1) < (rhs.segment, rhs.isStart ? 0 : 1)
	}
}

struct Junction: Hashable {
	var point: Point
	var layer: Int
}

protocol RoutedSegment: Equatable {
	var start: Point { get set }
	var end: Point { get set }
	var layer: Int { get }
	func canFuse(with other: Self) -> Bool
	func joining(_ other: Self, from start: Point, to end: Point) -> Self
}

extension Trace: RoutedSegment {
	func canFuse(with other: Trace) -> Bool { width == other.width && net == other.net }
	func joining(_ other: Trace, from start: Point, to end: Point) -> Trace {
		Trace(start: start, end: end, width: max(width, other.width), layer: layer, net: net ?? other.net)
	}
}

extension Wire: RoutedSegment {
	var layer: Int { 0 }
	func canFuse(with other: Wire) -> Bool { true }
	func joining(_ other: Wire, from start: Point, to end: Point) -> Wire { Wire(start: start, end: end) }
}

enum RoutingAngles {
	case orthogonal, octilinear

	func allows(_ offset: Point) -> Bool {
		switch self {
		case .orthogonal: offset.x == 0 || offset.y == 0
		case .octilinear: offset.isOctilinear
		}
	}

	func bends(_ arriving: Point, to next: Point) -> Bool {
		arriving.turn(to: next).map { $0 <= (self == .orthogonal ? 2 : 1) } ?? true
	}

	func path(from start: Point, to end: Point, heading: Point = .zero) -> [Point] {
		guard start != end else { return [start] }
		guard !allows(end - start) else { return [start, end] }
		let direction = heading == .zero ? (snapped90(from: start, to: end) - start).heading : heading
		return [start, corner(from: start, to: end, heading: direction, leaving: .zero), end]
	}

	func corner(from start: Point, to end: Point, heading: Point, leaving: Point) -> Point {
		if self == .octilinear { return bend(from: start, to: end, heading: heading, leaving: leaving) }
		let horizontal = Point(x: end.x, y: start.y)
		let vertical = Point(x: start.x, y: end.y)
		let (kept, other) = heading.x != 0 ? (horizontal, vertical) : (vertical, horizontal)
		return bends(-leaving, to: kept - start) ? kept : other
	}
}

struct RouteTerminal {
	var figure: Figure
	var layers: ClosedRange<Int>
	var moving: Bool = false

	func contains(_ point: Point, layer: Int) -> Bool { layers.contains(layer) && figure.contains(point) }
}

struct RouteGeometry<Segment: RoutedSegment> {
	var segments: [Segment]
	var terminals: [RouteTerminal]
	var angles: RoutingAngles
}

extension RouteGeometry {
	func isTerminal(_ point: Point, layer: Int) -> Bool {
		terminals.contains { $0.contains(point, layer: layer) }
	}

	func attachedEnds(to selected: Set<Int>) -> Set<RouteEnd> {
		var joints: Set<Junction> = []
		for index in selected where segments.indices.contains(index) {
			let segment = segments[index]
			for point in [segment.start, segment.end] where !isTerminal(point, layer: segment.layer) {
				joints.insert(Junction(point: point, layer: segment.layer))
			}
		}
		var ends: Set<RouteEnd> = []
		for (index, segment) in segments.enumerated() where !selected.contains(index) {
			for isStart in [true, false] {
				let point = isStart ? segment.start : segment.end
				if joints.contains(Junction(point: point, layer: segment.layer)) || terminals.contains(where: {
					$0.moving && $0.contains(point, layer: segment.layer)
				}) { ends.insert(RouteEnd(segment: index, isStart: isStart)) }
			}
		}
		return ends
	}

	private subscript(point end: RouteEnd) -> Point {
		get { end.isStart ? segments[end.segment].start : segments[end.segment].end }
		set {
			if end.isStart {
				segments[end.segment].start = newValue
			} else {
				segments[end.segment].end = newValue
			}
		}
	}

	@discardableResult
	mutating func move(_ refs: Set<Int>, by delta: Point, grid: µm) -> [Int: Int]? {
		let stored = self
		let held = heldPoints()
		let attached = attachedEnds(to: refs)
		let stretched = stretchedJoints(of: refs, following: attached, by: delta)
		let headings = headings(of: attached)
		let anchored = angles == .orthogonal ? (0 ..< segments.count).flatMap { index in
			[true, false].compactMap { isStart -> RouteEnd? in
				let end = RouteEnd(segment: index, isStart: isStart)
				guard refs.contains(index) || attached.contains(end), terminals.contains(where: {
					!$0.moving && $0.contains(self[point: end], layer: segments[index].layer)
				}) else { return nil }
				return end
			}
		} : []

		for index in refs where segments.indices.contains(index) {
			segments[index].start = segments[index].start + delta
			segments[index].end = segments[index].end + delta
		}
		for index in terminals.indices where terminals[index].moving {
			terminals[index].figure = terminals[index].figure.translated(by: delta)
		}
		for end in attached {
			self[point: end] = self[point: end] + delta
		}
		for (end, point) in stretched {
			self[point: end] = point
		}
		for end in attached.sorted(by: RouteEnd.order) where stretched[end] == nil {
			guard let heading = headings[end] else { continue }
			realign(end, heading: heading, moving: attached, with: refs)
		}

		var bridged: Set<Junction> = []
		for end in anchored {
			let anchor = stored[point: end]
			let junction = Junction(point: anchor, layer: segments[end.segment].layer)
			guard bridged.insert(junction).inserted else { continue }
			let path = angles.path(from: anchor, to: self[point: end])
			for (start, finish) in zip(path, path.dropFirst()) {
				segments.append(segments[end.segment].joining(segments[end.segment], from: start, to: finish))
			}
		}

		let changed = disturbed(from: stored.segments)
		var seen: Set<Junction> = []
		let touched = (changed + held.filter { !isTerminal($0.point, layer: $0.layer) })
			.filter { seen.insert($0).inserted }
		let fused = fuse(touching: stored.segments, disturbed: changed)

		for junction in touched where !chamfer(at: junction, grid: grid) {
			guard stored.wasSharp(at: junction, movedBy: delta) else {
				self = stored
				return nil
			}
		}
		return fused
	}

	private func stretchedJoints(
		of refs: Set<Int>,
		following attached: Set<RouteEnd>,
		by delta: Point
	) -> [RouteEnd: Point] {
		var joints: [(moved: RouteEnd, stayed: RouteEnd)] = []
		var points: [RouteEnd: Point] = [:]

		for index in refs where segments.indices.contains(index) {
			for isStart in [true, false] {
				let moved = RouteEnd(segment: index, isStart: isStart)
				let point = self[point: moved]
				let layer = segments[index].layer
				if isTerminal(point, layer: layer) {
					if angles == .orthogonal, !terminals.contains(where: {
						$0.moving && $0.contains(point, layer: layer)
					}) {
						let leg = point - self[point: moved.other]
						let normal = Point(x: -leg.y, y: leg.x)
						points[moved] = crossing(line: point + delta, leg, line: point, normal)
					}
					continue
				}

				var others: [RouteEnd] = []
				for (other, trace) in segments.enumerated()
				where other != index && trace.layer == layer {
					if trace.start == point { others.append(RouteEnd(segment: other, isStart: true)) }
					if trace.end == point { others.append(RouteEnd(segment: other, isStart: false)) }
				}
				guard others.count <= 1 else { return [:] }
				guard let stayed = others.first, !refs.contains(stayed.segment) else { continue }
				joints.append((moved, stayed))
			}
		}
		guard !joints.isEmpty || !points.isEmpty else { return [:] }

		for (moved, stayed) in joints {
			let point = self[point: moved]
			let leg = point - self[point: moved.other]
			let stem = point - self[point: stayed.other]
			guard let crossing = crossing(line: point + delta, leg, line: point, stem)
			else { return [:] }

			points[moved] = crossing
			points[stayed] = crossing
		}

		func settled(_ end: RouteEnd) -> Point {
			if let point = points[end] { return point }
			let follows = refs.contains(end.segment) || attached.contains(end)
			return self[point: end] + (follows ? delta : .zero)
		}
		for end in points.keys {
			let before = self[point: end] - self[point: end.other]
			let after = settled(end) - settled(end.other)
			guard after.runsAlong(before) || (after == .zero && !refs.contains(end.segment))
			else { return [:] }
		}
		return points
	}

	private func heldPoints() -> [Junction] {
		segments.flatMap { segment in
			[segment.start, segment.end].filter { point in
				terminals.contains { $0.moving && $0.contains(point, layer: segment.layer) }
			}.map { Junction(point: $0, layer: segment.layer) }
		}
	}

	private func disturbed(from before: [Segment]) -> [Junction] {
		var points: [Junction] = []
		for index in segments.indices
		where index >= before.count || segments[index] != before[index] {
			points.append(Junction(point: segments[index].start, layer: segments[index].layer))
			points.append(Junction(point: segments[index].end, layer: segments[index].layer))
		}
		return points
	}

	func turn(at junction: Junction) -> Int? {
		guard let (first, second) = joint(at: junction) else { return nil }
		let arriving = junction.point - self[point: first.other]
		return arriving.turn(to: self[point: second.other] - junction.point)
	}

	private func wasSharp(at junction: Junction, movedBy delta: Point) -> Bool {
		isSharp(at: junction)
			|| isSharp(at: Junction(point: junction.point - delta, layer: junction.layer))
	}

	private func isSharp(at junction: Junction) -> Bool {
		guard let (first, second) = joint(at: junction) else { return false }
		let arriving = junction.point - self[point: first.other]
		return !angles.bends(arriving, to: self[point: second.other] - junction.point)
	}

	private mutating func chamfer(at junction: Junction, grid: µm) -> Bool {
		guard let (first, second) = joint(at: junction) else { return true }

		let point = junction.point
		let legs = (self[point: first.other] - point, self[point: second.other] - point)
		let arriving = -legs.0
		guard !angles.bends(arriving, to: legs.1) else { return true }
		guard angles == .octilinear, arriving.turn(to: legs.1) == 2 else { return false }

		let step = Int(grid)
		guard step > 0,
			max(abs(legs.0.x), abs(legs.0.y)) > step,
			max(abs(legs.1.x), abs(legs.1.y)) > step
		else { return false }

		let corners = (point + legs.0.heading * step, point + legs.1.heading * step)

		self[point: first] = corners.0
		self[point: second] = corners.1
		segments.append(
			segments[first.segment].joining(segments[second.segment], from: corners.0, to: corners.1)
		)
		return true
	}

	private mutating func fuse(touching before: [Segment], disturbed: [Junction]) -> [Int: Int] {
		var absorbed: [Int: Int] = [:]
		var pending = disturbed

		var dead: Set<Int> = []
		for (index, trace) in segments.enumerated()
		where (index >= before.count || trace != before[index]) && trace.start == trace.end {
			dead.insert(index)
		}
		while let junction = pending.popLast() {
			guard let (kept, gone) = straightJoint(at: junction, ignoring: dead)
			else { continue }

			let far = self[point: gone.other]
			self[point: kept] = far
			dead.insert(gone.segment)
			absorbed[gone.segment] = kept.segment
			pending.append(Junction(point: far, layer: junction.layer))
		}

		var moved: [Int: Int] = [:]
		var surviving = 0
		for index in segments.indices where !dead.contains(index) {
			moved[index] = surviving
			surviving += 1
		}
		for (index, into) in absorbed {
			var target = into
			while let next = absorbed[target] { target = next }
			moved[index] = moved[target]
		}
		segments.remove(at: dead)
		return moved
	}

	private func joint(
		at junction: Junction,
		ignoring dead: Set<Int> = []
	) -> (RouteEnd, RouteEnd)? {
		guard !isTerminal(junction.point, layer: junction.layer) else { return nil }

		var ends: [RouteEnd] = []
		for (index, trace) in segments.enumerated()
		where !dead.contains(index) && trace.layer == junction.layer {
			if trace.start == junction.point { ends.append(RouteEnd(segment: index, isStart: true)) }
			if trace.end == junction.point { ends.append(RouteEnd(segment: index, isStart: false)) }
			guard ends.count <= 2 else { return nil }
		}
		guard ends.count == 2 else { return nil }
		return (ends[0], ends[1])
	}

	private func straightJoint(
		at junction: Junction,
		ignoring dead: Set<Int>
	) -> (RouteEnd, RouteEnd)? {
		guard let (first, second) = joint(at: junction, ignoring: dead),
			segments[first.segment].canFuse(with: segments[second.segment])
		else { return nil }

		let a = self[point: first.other] - junction.point
		let b = self[point: second.other] - junction.point
		guard a.x * b.y == a.y * b.x, a.x * b.x + a.y * b.y < 0 else { return nil }

		return (first, second)
	}

	private func headings(of ends: Set<RouteEnd>) -> [RouteEnd: Point] {
		var headings: [RouteEnd: Point] = [:]
		for end in ends {
			let offset = self[point: end.other] - self[point: end]
			guard angles.allows(offset) || angles == .orthogonal else { continue }
			headings[end] = angles == .orthogonal
				? (snapped90(from: .zero, to: offset)).heading : offset.heading
		}
		return headings
	}

	private mutating func realign(
		_ end: RouteEnd,
		heading: Point,
		moving: Set<RouteEnd>,
		with refs: Set<Int>
	) {
		let moved = self[point: end]
		let anchor = self[point: end.other]
		guard !angles.allows(anchor - moved) else { return }
		guard !slide(end, heading: heading, moving: moving, with: refs) else { return }

		let joint = self.heading(leaving: moved, layer: segments[end.segment].layer, ignoring: end.segment)
		let corner = angles.corner(from: moved, to: anchor, heading: heading, leaving: joint ?? .zero)
		segments.append(modifying(segments[end.segment]) { trace in
			trace.start = corner
			trace.end = anchor
		})
		self[point: end.other] = corner
	}

	private mutating func slide(
		_ end: RouteEnd,
		heading: Point,
		moving: Set<RouteEnd>,
		with refs: Set<Int>
	) -> Bool {
		let anchor = self[point: end.other]
		guard let next = continuation(of: end.segment, at: anchor), !refs.contains(next)
		else { return false }

		let corner = RouteEnd(segment: next, isStart: segments[next].start == anchor)
		guard !moving.contains(corner), !moving.contains(corner.other) else { return false }

		let far = self[point: corner.other]
		let offset = anchor - far
		guard angles.allows(offset),
			let slid = crossing(self[point: end], heading, far, offset.heading)
		else { return false }

		self[point: end.other] = slid
		self[point: corner] = slid
		return true
	}

	private func isBranchInterior(_ point: Point, layer: Int) -> Bool {
		angles == .orthogonal && segments.contains {
			$0.layer == layer && $0.start != point && $0.end != point
				&& distance(from: point, to: $0.start, $0.end) <= 1.0
		}
	}

	func run(of index: Int) -> Set<Int> {
		guard segments.indices.contains(index) else { return [] }

		var run: Set<Int> = [index]
		var pending = [index]

		while let current = pending.popLast() {
			for point in [segments[current].start, segments[current].end] {
				guard let next = continuation(of: current, at: point), run.insert(next).inserted
				else { continue }
				pending.append(next)
			}
		}
		return run
	}

	func continuation(of index: Int, at point: Point) -> Int? {
		let layer = segments[index].layer
		guard !isTerminal(point, layer: layer), !isBranchInterior(point, layer: layer) else { return nil }

		var corner: Int?
		for (other, trace) in segments.enumerated()
		where other != index && trace.layer == layer
			&& (trace.start == point || trace.end == point) {
			guard corner == nil else { return nil }
			corner = other
		}
		return corner
	}

	func heading(leaving point: Point, layer: Int, ignoring skipped: Int? = nil) -> Point? {
		guard !isTerminal(point, layer: layer), !isBranchInterior(point, layer: layer) else { return nil }

		var heading: Point?
		for (index, trace) in segments.enumerated()
		where index != skipped && trace.layer == layer
			&& (trace.start == point || trace.end == point) {
			let offset = (trace.start == point ? trace.end : trace.start) - point
			guard heading == nil, angles.allows(offset), offset != .zero else { return nil }
			heading = offset.heading
		}
		return heading
	}

}

private extension Figure {
	func translated(by delta: Point) -> Figure {
		switch self {
		case let .rect(rect): .rect(Rect(origin: rect.origin + delta, size: rect.size))
		case let .round(point, diameter): .round(point + delta, diameter)
		case let .segment(start, end, width): .segment(start + delta, end + delta, width)
		}
	}
}
