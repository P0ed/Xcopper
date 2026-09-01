struct Net: Hashable, Codable, Identifiable {
	var id: Int
	var name: String
}

struct Trace: Hashable, Codable {
	var start: Pt
	var end: Pt
	var width: Nm
	var layer: Int
	var net: Net.ID?
}

/// One end of a trace, the granularity at which copper follows a footprint it
/// is soldered to
struct TraceEnd: Hashable {
	var trace: Int
	var isStart: Bool

	/// The other end of the same segment, what this one runs to
	var other: TraceEnd { TraceEnd(trace: trace, isStart: !isStart) }

	static func order(_ lhs: TraceEnd, _ rhs: TraceEnd) -> Bool {
		(lhs.trace, lhs.isStart ? 0 : 1) < (rhs.trace, rhs.isStart ? 0 : 1)
	}
}

/// A point on one layer, where copper meets copper
struct Junction: Hashable {
	var point: Pt
	var layer: Int
}

struct Via: Hashable, Codable {
	var at: Pt
	var drill: Nm
	var pad: Nm
	var from: Int
	var to: Int
	var net: Net.ID?

	var span: ClosedRange<Int> { min(from, to) ... max(from, to) }

	func spans(_ layer: Int) -> Bool { span.contains(layer) }
}

/// Non plated mounting hole
struct Hole: Hashable, Codable {
	var at: Pt
	var diameter: Nm
}

struct Pad: Hashable, Codable {
	enum Shape: Int, Codable { case rect, oval }

	var at: Pt
	var size: Size
	var shape: Shape
	var drill: Nm
	var layer: Int
	var name: String
	var net: Net.ID?

	var isThrough: Bool { drill > 0 }
}

struct Footprint: Hashable, Codable {
	var reference: String
	var value: String
	var at: Pt
	var rotation: Rotation
	var flipped: Bool
	var pads: [Pad]
	var body: Rect
}

struct Rules: Hashable, Codable {
	var clearance: Nm
	var traceWidth: Nm
	var viaDrill: Nm
	var viaPad: Nm

	static var `default`: Rules {
		Rules(
			clearance: .mm(0.33),
			traceWidth: .mm(0.47),
			viaDrill: .mm(0.5),
			viaPad: .mm(0.9)
		)
	}
}

struct Board: Equatable, Codable {
	var size: Size
	var stack: Stack
	var planes: [Net.ID?]
	var traces: [Trace]
	var vias: [Via]
	var holes: [Hole]
	var footprints: [Footprint]
	var rules: Rules
}

extension Board {

	init(size: Size = .init(width: .inches(4), height: .inches(6)), stack: Stack = .six) {
		self.size = size
		self.stack = stack
		planes = .init(repeating: nil, count: stack.count)
		traces = []
		vias = []
		holes = []
		footprints = []
		rules = .default
	}

	var bounds: Rect { Rect(origin: .zero, size: size) }

	func plane(_ layer: Int) -> Net.ID? {
		planes.indices.contains(layer) ? planes[layer] : nil
	}
}

extension Footprint {

	/// Pads in board coordinates, with rotation and side applied
	var placedPads: [Pad] {
		pads.map { pad in
			modifying(pad) { pad in
				pad.at = place(pad.at)
				pad.size = rotation.isQuarter ? pad.size.swapped : pad.size
				pad.layer = pad.isThrough ? pad.layer : (flipped ? 1 - pad.layer : pad.layer)
			}
		}
	}

	/// Body outline in board coordinates
	var placedBody: Rect {
		Rect(
			center: place(body.center),
			size: rotation.isQuarter ? body.size.swapped : body.size
		)
	}

	/// Body and pads together, everything the part covers on the board
	var placedExtent: Rect {
		Rect.union([placedBody] + placedPads.map { pad in pad.figure.bounds }) ?? placedBody
	}

	func place(_ local: Pt) -> Pt {
		(flipped ? local.mirroredX : local).rotated(rotation) + at
	}

	/// Copper layer a placed pad occupies on a board with `stack`
	func layer(of pad: Pad, in stack: Stack) -> Int {
		pad.layer == 0 ? stack.top : stack.bottom
	}
}

extension Board {

	mutating func resize(size: Size) {
		self.size = size
	}

	mutating func restack(_ stack: Stack) {
		let old = self.stack
		self.stack = stack
		planes = (0 ..< stack.count).map { layer in
			old.contains(layer) && stack.isInternal(layer) ? planes[layer] : nil
		}
		traces.removeAll { !stack.contains($0.layer) }
		vias.modifyEach { via in
			via.from = min(via.from, stack.bottom)
			via.to = min(via.to, stack.bottom)
		}
		vias.removeAll { $0.from == $0.to }
	}

	/// Objects dropped by restacking to `stack`
	func restackLoss(_ stack: Stack) -> Int {
		traces.count { !stack.contains($0.layer) }
			+ vias.count { min($0.from, stack.bottom) == min($0.to, stack.bottom) }
	}

	/// Forgets every reference to `id`, leaving the net table to `Design`
	mutating func clearNet(_ id: Net.ID) {
		planes.modifyEach { plane in if plane == id { plane = nil } }
		traces.modifyEach { trace in if trace.net == id { trace.net = nil } }
		vias.modifyEach { via in if via.net == id { via.net = nil } }
		footprints.modifyEach { footprint in
			footprint.pads.modifyEach { pad in if pad.net == id { pad.net = nil } }
		}
	}

	mutating func setPlane(_ net: Net.ID?, on layer: Int) {
		guard stack.isInternal(layer), planes.indices.contains(layer) else { return }
		planes[layer] = net
	}
}

extension Board {

	/// Where `footprint`, built at the origin, can stand clear of everything the
	/// board already carries
	func parking(for footprint: Footprint) -> Pt {
		Xcopper.parking(footprint.placedExtent, in: bounds, clear: occupied)
	}

	/// What every object on the board covers, whatever layer it is on
	private var occupied: [Rect] {
		footprints.map(\.placedExtent)
			+ traces.map { trace in Figure.segment(trace.start, trace.end, trace.width).bounds }
			+ vias.map { via in Figure.round(via.at, via.pad).bounds }
			+ holes.map { hole in Figure.round(hole.at, hole.diameter).bounds }
	}
}

extension Board {

	subscript(net ref: Ref) -> Net.ID? {
		get {
			switch ref {
			case let .trace(index): traces.indices.contains(index) ? traces[index].net : nil
			case let .via(index): vias.indices.contains(index) ? vias[index].net : nil
			case .hole, .footprint: nil
			}
		}
		set {
			switch ref {
			case let .trace(index):
				if traces.indices.contains(index) { traces[index].net = newValue }
			case let .via(index):
				if vias.indices.contains(index) { vias[index].net = newValue }
			case let .footprint(index):
				if footprints.indices.contains(index) {
					footprints[index].pads.modifyEach { pad in pad.net = newValue }
				}
			case .hole:
				break
			}
		}
	}

	/// Trace ends that follow `refs`: one landing on a pad of a moving footprint
	/// and one soldered to the end of a moving segment. Attachment is the same
	/// pad-contains-endpoint test the ratsnest uses, so copper follows a part
	/// exactly when it counted as joined to it, and a joint held by a pad or a
	/// via stays with the terminal rather than with the copper leaving it.
	/// Traces in `refs` already move whole and are left out.
	func attachedEnds(to refs: Set<Ref>) -> Set<TraceEnd> {
		var pads: [(figure: Figure, layers: ClosedRange<Int>)] = []
		var joints: [Int: Set<Pt>] = [:]

		for case let .footprint(index) in refs where footprints.indices.contains(index) {
			let footprint = footprints[index]
			for pad in footprint.placedPads {
				let layer = footprint.layer(of: pad, in: stack)
				pads.append((
					pad.figure,
					pad.isThrough ? stack.top ... stack.bottom : layer ... layer
				))
			}
		}
		for case let .trace(index) in refs where traces.indices.contains(index) {
			let trace = traces[index]
			for point in [trace.start, trace.end] where !isTerminal(point, layer: trace.layer) {
				joints[trace.layer, default: []].insert(point)
			}
		}
		guard !pads.isEmpty || !joints.isEmpty else { return [] }

		var ends: Set<TraceEnd> = []
		for (index, trace) in traces.enumerated() where !refs.contains(.trace(index)) {
			for (figure, layers) in pads where layers.contains(trace.layer) {
				if figure.contains(trace.start) { ends.insert(TraceEnd(trace: index, isStart: true)) }
				if figure.contains(trace.end) { ends.insert(TraceEnd(trace: index, isStart: false)) }
			}
			guard let points = joints[trace.layer] else { continue }
			if points.contains(trace.start) { ends.insert(TraceEnd(trace: index, isStart: true)) }
			if points.contains(trace.end) { ends.insert(TraceEnd(trace: index, isStart: false)) }
		}
		return ends
	}

	/// The point one end of a trace sits on
	private subscript(point end: TraceEnd) -> Pt {
		get { end.isStart ? traces[end.trace].start : traces[end.trace].end }
		set {
			if end.isStart {
				traces[end.trace].start = newValue
			} else {
				traces[end.trace].end = newValue
			}
		}
	}

	/// Moves `refs`, taking the copper it is soldered to along with it, putting
	/// the segments it stretched back on the 45 degree grid and fusing what it
	/// leaves running straight. Returns `refs` as they stand afterwards, since
	/// fusing renumbers the copper.
	///
	/// A segment dragged off a corner stretches the segment it hangs off
	/// rather than carrying it: both keep the heading they were drawn at and
	/// the joint slides to where those headings cross now, so either one
	/// changes length. Copper a pad carries off has no such say and follows
	/// the pad, and so does a joint the stretch cannot work out.
	///
	/// No drag leaves copper turning a right angle: a corner that comes out
	/// square is broken into the two 45 degree bends it is really made of, on
	/// a `grid` step of either leg. A corner no chain of 45s reaches, copper
	/// doubled back on itself or a leg with no step to spare, refuses the
	/// whole move: the board is left as it stood and nil comes back, so a
	/// refused drag is an edit that never happened rather than one that
	/// changed nothing.
	@discardableResult
	mutating func move(_ refs: Set<Ref>, by delta: Pt, grid: Nm) -> Set<Ref>? {
		let stored = self
		let held = heldPoints(movedBy: refs)
		let attached = attachedEnds(to: refs)
		let stretched = stretchedJoints(of: refs, following: attached, by: delta)
		let headings = headings(of: attached)

		for ref in refs {
			switch ref {
			case let .trace(index) where traces.indices.contains(index):
				traces[index].start = traces[index].start + delta
				traces[index].end = traces[index].end + delta
			case let .via(index) where vias.indices.contains(index):
				vias[index].at = vias[index].at + delta
			case let .hole(index) where holes.indices.contains(index):
				holes[index].at = holes[index].at + delta
			case let .footprint(index) where footprints.indices.contains(index):
				footprints[index].at = footprints[index].at + delta
			default:
				break
			}
		}
		for end in attached {
			self[point: end] = self[point: end] + delta
		}
		for (end, point) in stretched {
			self[point: end] = point
		}
		for end in attached.sorted(by: TraceEnd.order) where stretched[end] == nil {
			guard let heading = headings[end] else { continue }
			realign(end, heading: heading, moving: attached, with: refs)
		}

		// A move that takes a pad or a via out from under a junction leaves a
		// plain corner where the copper used to be joined, so that counts as
		// disturbed too. A joint reached from both sides is only worth looking
		// over once.
		let changed = disturbed(from: stored.traces)
		var seen: Set<Junction> = []
		let touched = (changed + held.filter { !isTerminal($0.point, layer: $0.layer) })
			.filter { seen.insert($0).inserted }
		let fused = fuse(touching: stored.traces, disturbed: changed)

		for junction in touched where !chamfer(at: junction, grid: grid) {
			guard stored.wasSharp(at: junction, movedBy: delta) else {
				self = stored
				return nil
			}
		}
		return Set(refs.compactMap { ref -> Ref? in
			guard case let .trace(index) = ref else { return ref }
			return fused[index].map(Ref.trace)
		})
	}

	/// Where the joints between copper that moved and copper left behind come
	/// to rest, worked out on the board as it stands before anything does.
	/// Both sides keep the heading they were drawn at and the joint slides to
	/// where those headings cross now, so the segment dragged changes length
	/// and so does the one it hangs off: the bottom of a U dragged towards the
	/// top comes out longer and the legs it hangs off shorter. A leg taken up
	/// to nothing is fused away with the rest.
	///
	/// Empty where the copper will not have it — a branch, which has no one
	/// heading to keep; two headings that never meet or meet off the
	/// nanometer; a leg the drag would run backwards; a dragged segment
	/// squeezed out of existence — and the drag falls back on carrying the
	/// joint along and folding the copper to suit. All of them or none: a
	/// gesture that stretched one joint and folded the next would be two
	/// edits wearing one drag.
	private func stretchedJoints(
		of refs: Set<Ref>,
		following attached: Set<TraceEnd>,
		by delta: Pt
	) -> [TraceEnd: Pt] {
		var joints: [(moved: TraceEnd, stayed: TraceEnd)] = []

		for case let .trace(index) in refs where traces.indices.contains(index) {
			for isStart in [true, false] {
				let moved = TraceEnd(trace: index, isStart: isStart)
				let point = self[point: moved]
				let layer = traces[index].layer
				guard !isTerminal(point, layer: layer) else { continue }

				var others: [TraceEnd] = []
				for (other, trace) in traces.enumerated()
				where other != index && trace.layer == layer {
					if trace.start == point { others.append(TraceEnd(trace: other, isStart: true)) }
					if trace.end == point { others.append(TraceEnd(trace: other, isStart: false)) }
				}
				guard others.count <= 1 else { return [:] }
				guard let stayed = others.first, !refs.contains(.trace(stayed.trace)) else { continue }
				joints.append((moved, stayed))
			}
		}
		guard !joints.isEmpty else { return [:] }

		var points: [TraceEnd: Pt] = [:]
		for (moved, stayed) in joints {
			let point = self[point: moved]
			let leg = point - self[point: moved.other]
			let stem = point - self[point: stayed.other]
			guard let crossing = crossing(line: point + delta, leg, line: point, stem)
			else { return [:] }

			points[moved] = crossing
			points[stayed] = crossing
		}

		func settled(_ end: TraceEnd) -> Pt {
			if let point = points[end] { return point }
			let follows = refs.contains(.trace(end.trace)) || attached.contains(end)
			return self[point: end] + (follows ? delta : .zero)
		}
		for end in points.keys {
			let before = self[point: end] - self[point: end.other]
			let after = settled(end) - settled(end.other)
			// Copper the stretch would run backwards is copper the drag has
			// pulled through itself. The segment left behind may be taken up
			// to nothing, since that fuses away, but the one dragged has to
			// come out of its own drag as copper.
			guard after.runsAlong(before) || (after == .zero && !refs.contains(.trace(end.trace)))
			else { return [:] }
		}
		return points
	}

	/// Joints held by a pad or a via that `refs` carries off, where the copper
	/// is joined rather than bent. Only a terminal that moves can be taken out
	/// from under a joint, so the copper the rest of the board holds down never
	/// comes into it and a drag costs the size of the edit, not of the document.
	private func heldPoints(movedBy refs: Set<Ref>) -> [Junction] {
		var figures: [(figure: Figure, layers: ClosedRange<Int>)] = []

		for ref in refs {
			switch ref {
			case let .footprint(index) where footprints.indices.contains(index):
				let footprint = footprints[index]
				for pad in footprint.placedPads {
					let layer = footprint.layer(of: pad, in: stack)
					figures.append((
						pad.figure,
						pad.isThrough ? stack.top ... stack.bottom : layer ... layer
					))
				}
			case let .via(index) where vias.indices.contains(index):
				let via = vias[index]
				figures.append((Figure.round(via.at, via.pad), via.span))
			default:
				break
			}
		}
		guard !figures.isEmpty else { return [] }

		var held: [Junction] = []
		for trace in traces {
			for (figure, layers) in figures where layers.contains(trace.layer) {
				if figure.contains(trace.start) {
					held.append(Junction(point: trace.start, layer: trace.layer))
				}
				if figure.contains(trace.end) {
					held.append(Junction(point: trace.end, layer: trace.layer))
				}
			}
		}
		return held
	}

	/// Every joint a move left different from `before`, the copper it has to
	/// look over again
	private func disturbed(from before: [Trace]) -> [Junction] {
		var points: [Junction] = []
		for index in traces.indices
		where index >= before.count || traces[index] != before[index] {
			points.append(Junction(point: traces[index].start, layer: traces[index].layer))
			points.append(Junction(point: traces[index].end, layer: traces[index].layer))
		}
		return points
	}

	/// How hard the copper turns at `junction`, in eighths of a turn. Nil where
	/// nothing turns there: a straight run, a branch, a terminal joining the
	/// copper instead, or a leg drawn at a free angle.
	func turn(at junction: Junction) -> Int? {
		guard let (first, second) = joint(at: junction) else { return nil }
		let arriving = junction.point - self[point: first.other]
		return arriving.turn(to: self[point: second.other] - junction.point)
	}

	/// Whether the copper was already turning harder than a board is built with
	/// where `junction` is now, or where a drag of `delta` brought it from.
	/// Copper found that sharp is left as sharp as it was found rather than
	/// holding the drag hostage.
	private func wasSharp(at junction: Junction, movedBy delta: Pt) -> Bool {
		isSharp(at: junction)
			|| isSharp(at: Junction(point: junction.point - delta, layer: junction.layer))
	}

	/// Whether the copper turns harder at `junction` than a board is built with
	private func isSharp(at junction: Junction) -> Bool {
		guard let (first, second) = joint(at: junction) else { return false }
		let arriving = junction.point - self[point: first.other]
		return !arriving.bends(to: self[point: second.other] - junction.point)
	}

	/// Breaks the right angle at `junction` into the two 45 degree bends it is
	/// really made of: each leg gives up one grid step and a short segment
	/// joins where they left off, the way the corner would have been drawn.
	/// Reports whether the copper there is something a board can be built
	/// with afterwards, which is how a move that cannot be squared away at
	/// all comes to be refused.
	private mutating func chamfer(at junction: Junction, grid: Nm) -> Bool {
		guard let (first, second) = joint(at: junction) else { return true }

		let point = junction.point
		let legs = (self[point: first.other] - point, self[point: second.other] - point)
		let arriving = -legs.0
		guard !arriving.bends(to: legs.1) else { return true }
		guard arriving.turn(to: legs.1) == 2 else { return false }

		let step = Int(grid)
		guard step > 0,
			max(abs(legs.0.x), abs(legs.0.y)) > step,
			max(abs(legs.1.x), abs(legs.1.y)) > step
		else { return false }

		// The wider of the two carries the corner, so breaking it never necks
		// the copper down
		let width = max(traces[first.trace].width, traces[second.trace].width)
		let net = traces[first.trace].net ?? traces[second.trace].net
		let corners = (point + legs.0.heading * step, point + legs.1.heading * step)

		self[point: first] = corners.0
		self[point: second] = corners.1
		traces.append(
			Trace(start: corners.0, end: corners.1, width: width, layer: junction.layer, net: net)
		)
		return true
	}

	/// Leaves the copper a move touched the way it would have been drawn:
	/// segments that now run head to tail in a straight line become the one
	/// segment they look like, and segments dragged down to nothing go away.
	/// `before` is the copper as it stood, so nothing the move left alone is
	/// disturbed, and `disturbed` is the joints it left different, already
	/// worked out. Returns where each old index went — a swallowed segment
	/// reports the one it is now part of, a collapsed one reports nothing.
	private mutating func fuse(touching before: [Trace], disturbed: [Junction]) -> [Int: Int] {
		var absorbed: [Int: Int] = [:]
		var pending = disturbed

		var dead: Set<Int> = []
		for (index, trace) in traces.enumerated()
		where (index >= before.count || trace != before[index]) && trace.start == trace.end {
			dead.insert(index)
		}
		while let junction = pending.popLast() {
			guard let (kept, gone) = straightJoint(at: junction, ignoring: dead)
			else { continue }

			let far = self[point: gone.other]
			self[point: kept] = far
			dead.insert(gone.trace)
			absorbed[gone.trace] = kept.trace
			pending.append(Junction(point: far, layer: junction.layer))
		}

		var moved: [Int: Int] = [:]
		var surviving = 0
		for index in traces.indices where !dead.contains(index) {
			moved[index] = surviving
			surviving += 1
		}
		for (index, into) in absorbed {
			var target = into
			while let next = absorbed[target] { target = next }
			moved[index] = moved[target]
		}
		traces.remove(at: dead)
		return moved
	}

	/// The two segment ends meeting at `junction` when the copper simply turns
	/// there: two ends, no branch, and no pad or via joining them instead
	private func joint(
		at junction: Junction,
		ignoring dead: Set<Int> = []
	) -> (TraceEnd, TraceEnd)? {
		guard !isTerminal(junction.point, layer: junction.layer) else { return nil }

		var ends: [TraceEnd] = []
		for (index, trace) in traces.enumerated()
		where !dead.contains(index) && trace.layer == junction.layer {
			if trace.start == junction.point { ends.append(TraceEnd(trace: index, isStart: true)) }
			if trace.end == junction.point { ends.append(TraceEnd(trace: index, isStart: false)) }
			guard ends.count <= 2 else { return nil }
		}
		guard ends.count == 2 else { return nil }
		return (ends[0], ends[1])
	}

	/// The joint at `junction` when the copper runs straight through it, with
	/// no bend and both sides drawn alike. The first is the end that stays, the
	/// second the end of the segment it swallows.
	private func straightJoint(
		at junction: Junction,
		ignoring dead: Set<Int>
	) -> (TraceEnd, TraceEnd)? {
		guard let (first, second) = joint(at: junction, ignoring: dead),
			traces[first.trace].width == traces[second.trace].width,
			traces[first.trace].net == traces[second.trace].net
		else { return nil }

		// Straight through: the two sides leave the point in opposite directions
		let a = self[point: first.other] - junction.point
		let b = self[point: second.other] - junction.point
		guard a.x * b.y == a.y * b.x, a.x * b.x + a.y * b.y < 0 else { return nil }

		return (first, second)
	}

	/// Direction each end ran along before the move. A segment drawn at a free
	/// angle has none, and is left the way it was drawn.
	private func headings(of ends: Set<TraceEnd>) -> [TraceEnd: Pt] {
		var headings: [TraceEnd: Pt] = [:]
		for end in ends {
			let offset = self[point: end.other] - self[point: end]
			guard offset.isOctilinear else { continue }
			headings[end] = offset.heading
		}
		return headings
	}

	/// Puts a segment one end of which followed a footprint back on the 45
	/// degree grid, sliding the corner it runs into when that corner is free to
	/// take up the slack and folding the segment in two when it is not. The
	/// fold leaves the end that moved along a heading the copper still soldered
	/// to it can turn into, so a drag never squares a corner off.
	private mutating func realign(
		_ end: TraceEnd,
		heading: Pt,
		moving: Set<TraceEnd>,
		with refs: Set<Ref>
	) {
		let moved = self[point: end]
		let anchor = self[point: end.other]
		guard !(anchor - moved).isOctilinear else { return }
		guard !slide(end, heading: heading, moving: moving, with: refs) else { return }

		let joint = self.heading(leaving: moved, layer: traces[end.trace].layer, ignoring: end.trace)
		let corner = bend(from: moved, to: anchor, heading: heading, leaving: joint ?? .zero)
		traces.append(modifying(traces[end.trace]) { trace in
			trace.start = corner
			trace.end = anchor
		})
		self[point: end.other] = corner
	}

	/// Slides the corner `end` runs into, so that both segments meeting there
	/// keep the direction they were drawn at. Fails on a corner that cannot
	/// take the move: a pad, a via, a branch, copper that is moving too, or a
	/// pair of directions that never meet.
	private mutating func slide(
		_ end: TraceEnd,
		heading: Pt,
		moving: Set<TraceEnd>,
		with refs: Set<Ref>
	) -> Bool {
		let anchor = self[point: end.other]
		guard let next = continuation(of: end.trace, at: anchor), !refs.contains(.trace(next))
		else { return false }

		let corner = TraceEnd(trace: next, isStart: traces[next].start == anchor)
		guard !moving.contains(corner), !moving.contains(corner.other) else { return false }

		let far = self[point: corner.other]
		let offset = anchor - far
		guard offset.isOctilinear,
			let slid = crossing(self[point: end], heading, far, offset.heading)
		else { return false }

		self[point: end.other] = slid
		self[point: corner] = slid
		return true
	}

	mutating func remove(_ refs: Set<Ref>) {
		traces.remove(at: refs.compactMap { if case let .trace(i) = $0 { i } else { nil } })
		vias.remove(at: refs.compactMap { if case let .via(i) = $0 { i } else { nil } })
		holes.remove(at: refs.compactMap { if case let .hole(i) = $0 { i } else { nil } })
		footprints.remove(at: refs.compactMap { if case let .footprint(i) = $0 { i } else { nil } })
	}

	mutating func rotate(_ refs: Set<Ref>, clockwise: Bool) {
		guard let pivot = bounds(of: refs)?.center else { return }
		let rotation: Rotation = clockwise ? .r90 : .r270

		func spin(_ point: Pt) -> Pt { (point - pivot).rotated(rotation) + pivot }

		for ref in refs {
			switch ref {
			case let .trace(index) where traces.indices.contains(index):
				traces[index].start = spin(traces[index].start)
				traces[index].end = spin(traces[index].end)
			case let .via(index) where vias.indices.contains(index):
				vias[index].at = spin(vias[index].at)
			case let .hole(index) where holes.indices.contains(index):
				holes[index].at = spin(holes[index].at)
			case let .footprint(index) where footprints.indices.contains(index):
				footprints[index].at = spin(footprints[index].at)
				footprints[index].rotation = clockwise
					? footprints[index].rotation.next
					: footprints[index].rotation.previous
			default:
				break
			}
		}
	}

	mutating func flip(_ refs: Set<Ref>) {
		for case let .footprint(index) in refs where footprints.indices.contains(index) {
			footprints[index].flipped.toggle()
		}
		for case let .trace(index) in refs where traces.indices.contains(index) {
			traces[index].layer = stack.bottom - traces[index].layer
		}
	}

	/// `used` holds the designators the other half of the document has spoken
	/// for, so a copy never takes the name of a part that already exists
	mutating func duplicate(
		_ refs: Set<Ref>,
		by delta: Pt,
		references used: Set<String> = []
	) -> Set<Ref> {
		var created: Set<Ref> = []
		for ref in refs.sorted(by: Ref.order) {
			switch ref {
			case let .trace(index) where traces.indices.contains(index):
				traces.append(modifying(traces[index]) { trace in
					trace.start = trace.start + delta
					trace.end = trace.end + delta
				})
				created.insert(.trace(traces.count - 1))
			case let .via(index) where vias.indices.contains(index):
				vias.append(modifying(vias[index]) { via in via.at = via.at + delta })
				created.insert(.via(vias.count - 1))
			case let .hole(index) where holes.indices.contains(index):
				holes.append(modifying(holes[index]) { hole in hole.at = hole.at + delta })
				created.insert(.hole(holes.count - 1))
			case let .footprint(index) where footprints.indices.contains(index):
				footprints.append(modifying(footprints[index]) { footprint in
					footprint.at = footprint.at + delta
					footprint.reference = nextReference(like: footprint.reference, besides: used)
				})
				created.insert(.footprint(footprints.count - 1))
			default:
				break
			}
		}
		return created
	}

	func nextReference(like reference: String, besides used: Set<String> = []) -> String {
		Xcopper.nextReference(like: reference, used: Set(footprints.map(\.reference)).union(used))
	}
}

extension Ref {

	static func order(_ lhs: Ref, _ rhs: Ref) -> Bool {
		lhs.index < rhs.index
	}

	var index: Int {
		switch self {
		case let .trace(index), let .via(index), let .hole(index), let .footprint(index): index
		}
	}
}
