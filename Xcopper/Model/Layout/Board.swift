struct Net: Hashable, Codable, Identifiable {
	var id: Int
	var name: String
}

struct Trace: Hashable, Codable {
	var start: Point
	var end: Point
	var width: Nm
	var layer: Int
	var net: Net.ID?
}

struct Via: Hashable, Codable {
	var at: Point
	var drill: Nm
	var pad: Nm
	var from: Int
	var to: Int
	var net: Net.ID?

	var span: ClosedRange<Int> { min(from, to) ... max(from, to) }

	func spans(_ layer: Int) -> Bool { span.contains(layer) }
}

struct Hole: Hashable, Codable {
	var at: Point
	var diameter: Nm
}

struct Pad: Hashable, Codable {
	enum Shape: Int, Codable { case rect, oval }

	var at: Point
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
	var at: Point
	var rotation: Rotation
	var flipped: Bool
	var pads: [Pad]
	var body: Rect
	var device: Device = .unknown
	var package: Package = .custom
	var component: Component?
	var inBOM: Bool = true
}

extension Footprint {

	enum CodingKeys: String, CodingKey {
		case reference, value, at, rotation, flipped, pads, body, device, package, component, inBOM
	}

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		reference = try values.decode(String.self, forKey: .reference)
		value = try values.decode(String.self, forKey: .value)
		at = try values.decode(Point.self, forKey: .at)
		rotation = try values.decode(Rotation.self, forKey: .rotation)
		flipped = try values.decode(Bool.self, forKey: .flipped)
		pads = try values.decode([Pad].self, forKey: .pads)
		body = try values.decode(Rect.self, forKey: .body)
		device = try values.decode(Device.self, forKey: .device)
		package = try values.decode(Package.self, forKey: .package)
		component = try values.decodeIfPresent(Component.self, forKey: .component)
		inBOM = try values.decodeIfPresent(Bool.self, forKey: .inBOM) ?? true
	}
}

struct Rules: Hashable, Codable {
	var clearance: Nm
	var traceWidth: Nm
	var viaDrill: Nm
	var viaPad: Nm

	static var `default`: Rules {
		Rules(
			clearance: .mm(0.3),
			traceWidth: .mm(0.4),
			viaDrill: .mm(0.5),
			viaPad: .mm(0.9)
		)
	}
}

struct Board: Equatable, Codable {
	var size: Size
	var stack: Stack
	var traces: [Trace]
	var vias: [Via]
	var holes: [Hole]
	var footprints: [Footprint]
	var rules: Rules
}

extension Board {

	init(size: Size = .init(width: .inches(4), height: .inches(6)), stack: Stack = .analog) {
		self.size = size
		self.stack = stack
		traces = []
		vias = []
		holes = []
		footprints = []
		rules = .default
	}

	var bounds: Rect { Rect(origin: .zero, size: size) }
}

extension Footprint {

	var placedPads: [Pad] {
		pads.map { pad in
			modifying(pad) { pad in
				pad.at = place(pad.at)
				pad.size = rotation.isQuarter ? pad.size.swapped : pad.size
				pad.layer = pad.isThrough ? pad.layer : (flipped ? 1 - pad.layer : pad.layer)
			}
		}
	}

	var placedBody: Rect {
		Rect(
			center: place(body.center),
			size: rotation.isQuarter ? body.size.swapped : body.size
		)
	}

	var placedExtent: Rect {
		Rect.union([placedBody] + placedPads.map { pad in pad.figure.bounds }) ?? placedBody
	}

	func place(_ local: Point) -> Point {
		(flipped ? local.mirroredX : local).rotated(rotation) + at
	}

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
		traces.removeAll { !old.isSignal($0.layer) }
		traces.modifyEach { trace in trace.layer = stack.signal(matching: trace.layer, in: old) }
		vias.modifyEach { via in
			via.from = stack.signal(matching: via.from, in: old)
			via.to = stack.signal(matching: via.to, in: old)
		}
		vias.removeAll { $0.from == $0.to }
	}

	mutating func mapNets(_ map: (Net.ID?) -> Net.ID?) {
		traces.modifyEach { $0.net = map($0.net) }
		vias.modifyEach { $0.net = map($0.net) }
		footprints.modifyEach { $0.pads.modifyEach { $0.net = map($0.net) } }
	}

	mutating func clearNet(_ id: Net.ID) {
		mapNets { $0 == id ? nil : $0 }
	}
}

extension Board {

	func parking(for footprint: Footprint) -> Point {
		parking(for: footprint, clear: occupied)
	}

	func parking(for footprint: Footprint, clear taken: [Rect]) -> Point {
		Xcopper.parking(footprint.placedExtent, in: bounds, clear: taken)
	}

	var occupied: [Rect] {
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
			case .hole, .footprint, .module: nil
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
			case .hole, .module:
				break
			}
		}
	}

	func routing(moving refs: Set<Ref> = []) -> RouteGeometry<Trace> {
		var terminals: [RouteTerminal] = []
		for (index, footprint) in footprints.enumerated() {
			for pad in footprint.placedPads {
				let layer = footprint.layer(of: pad, in: stack)
				terminals.append(RouteTerminal(
					figure: pad.figure,
					layers: pad.isThrough ? stack.top ... stack.bottom : layer ... layer,
					moving: refs.contains(.footprint(index))
				))
			}
		}
		for (index, via) in vias.enumerated() {
			terminals.append(RouteTerminal(
				figure: .round(via.at, via.pad), layers: via.span,
				moving: refs.contains(.via(index)), carriesAttachments: false
			))
		}
		return RouteGeometry(segments: traces, terminals: terminals, angles: .octilinear)
	}

	func attachedEnds(to refs: Set<Ref>) -> Set<RouteEnd> {
		routing(moving: refs).attachedEnds(to: Set(refs.compactMap {
			if case let .trace(index) = $0 { index } else { nil }
		}))
	}

	func turn(at junction: Junction) -> Int? { routing().turn(at: junction) }

	@discardableResult
	mutating func move(_ refs: Set<Ref>, by delta: Point, grid: Nm) -> Set<Ref>? {
		var route = routing(moving: refs)
		let selected = Set(refs.compactMap { if case let .trace(index) = $0 { index } else { nil } })
		guard let mapped = route.move(selected, by: delta, grid: grid) else { return nil }
		traces = route.segments
		for ref in refs {
			switch ref {
			case let .via(index) where vias.indices.contains(index):
				vias[index].at = vias[index].at + delta
			case let .hole(index) where holes.indices.contains(index):
				holes[index].at = holes[index].at + delta
			case let .footprint(index) where footprints.indices.contains(index):
				footprints[index].at = footprints[index].at + delta
			default: break
			}
		}
		return Set(refs.compactMap { ref in
			guard case let .trace(index) = ref else { return ref }
			return mapped[index].map(Ref.trace)
		})
	}

	mutating func remove(_ refs: Set<Ref>) {
		traces.remove(at: refs.compactMap { if case let .trace(i) = $0 { i } else { nil } })
		vias.remove(at: refs.compactMap { if case let .via(i) = $0 { i } else { nil } })
		holes.remove(at: refs.compactMap { if case let .hole(i) = $0 { i } else { nil } })
		footprints.remove(at: refs.compactMap { if case let .footprint(i) = $0 { i } else { nil } })
	}

	mutating func rotate(_ refs: Set<Ref>, clockwise: Bool, around center: Point? = nil) {
		guard let pivot = center ?? bounds(of: refs)?.center else { return }
		let rotation: Rotation = clockwise ? .r90 : .r270

		func spin(_ point: Point) -> Point { (point - pivot).rotated(rotation) + pivot }

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

	mutating func duplicate(_ refs: Set<Ref>, by delta: Point) -> Set<Ref> {
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
				})
				created.insert(.footprint(footprints.count - 1))
			default:
				break
			}
		}
		return created
	}
}

extension Ref {

	static func order(_ lhs: Ref, _ rhs: Ref) -> Bool {
		lhs.index < rhs.index
	}

	var index: Int {
		switch self {
		case .module: Int.max
		case let .trace(index), let .via(index), let .hole(index), let .footprint(index): index
		}
	}
}
