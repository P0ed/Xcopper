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
			clearance: .mm(0.2),
			traceWidth: .mm(0.25),
			viaDrill: .mm(0.3),
			viaPad: .mm(0.6)
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

	init(size: Size = .init(width: .mm(50), height: .mm(50)), stack: Stack = .two) {
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

	mutating func move(_ refs: Set<Ref>, by delta: Pt) {
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
