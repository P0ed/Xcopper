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

	/// Trace ends landing on a pad of a footprint in `refs`. Attachment is the
	/// same pad-contains-endpoint test the ratsnest uses, so copper follows a
	/// part exactly when it counted as joined to it. Traces in `refs` already
	/// move whole and are left out.
	func attachedEnds(to refs: Set<Ref>) -> Set<TraceEnd> {
		var pads: [(figure: Figure, layers: ClosedRange<Int>)] = []

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
		guard !pads.isEmpty else { return [] }

		var ends: Set<TraceEnd> = []
		for (index, trace) in traces.enumerated() where !refs.contains(.trace(index)) {
			for (figure, layers) in pads where layers.contains(trace.layer) {
				if figure.contains(trace.start) { ends.insert(TraceEnd(trace: index, isStart: true)) }
				if figure.contains(trace.end) { ends.insert(TraceEnd(trace: index, isStart: false)) }
			}
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

	/// Moves `refs`, dragging the loose ends of whatever copper lands on a
	/// moving footprint along with it and putting the segments it stretched
	/// back on the 45 degree grid
	mutating func move(_ refs: Set<Ref>, by delta: Pt) {
		let attached = attachedEnds(to: refs)
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
		for end in attached.sorted(by: TraceEnd.order) {
			guard let heading = headings[end] else { continue }
			realign(end, heading: heading, moving: attached, with: refs)
		}
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
	/// take up the slack and folding the segment in two when it is not
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

		let corner = bend(from: moved, to: anchor, heading: heading)
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

	mutating func duplicate(_ refs: Set<Ref>, by delta: Pt) -> Set<Ref> {
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
					footprint.reference = nextReference(like: footprint.reference)
				})
				created.insert(.footprint(footprints.count - 1))
			default:
				break
			}
		}
		return created
	}

	func nextReference(like reference: String) -> String {
		Xcopper.nextReference(like: reference, used: Set(footprints.map(\.reference)))
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
