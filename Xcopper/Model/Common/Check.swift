import Foundation

struct Violation: Hashable {

	enum Kind: Int, Hashable, Comparable {
		case short
		case clearance
		case hole
		case edge
		case unrouted

		static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }
	}

	var kind: Kind
	var at: Pt
	var layer: Int?
	var refs: Set<Ref>
	var text: String
}

extension Violation {

	static func order(_ lhs: Violation, _ rhs: Violation) -> Bool {
		lhs.kind != rhs.kind ? lhs.kind < rhs.kind : Pt.order(lhs.at, rhs.at)
	}
}

extension Design {

	func check() -> [Violation] {
		(faults() + unrouted()).sorted(by: Violation.order)
	}

	func faults() -> [Violation] {
		let clearance = Int(board.rules.clearance)
		let objects = board.objects

		return board.stack.copper.flatMap { layer in
			clashes(among: objects, on: layer, clearance: clearance)
		} + strays(among: objects, clearance: clearance)
	}
}

private struct Object {
	var figure: Figure
	var net: Net.ID?
	var ref: Ref
	var layers: ClosedRange<Int>
	var drilled: Bool
	var bounds: Rect

	init(_ figure: Figure, net: Net.ID?, ref: Ref, layers: ClosedRange<Int>, drilled: Bool = false) {
		self.figure = figure
		self.net = net
		self.ref = ref
		self.layers = layers
		self.drilled = drilled
		bounds = figure.bounds
	}

	func shared(with other: Object) -> Int? {
		let layer = max(layers.lowerBound, other.layers.lowerBound)
		return layers.contains(layer) && other.layers.contains(layer) ? layer : nil
	}
}

private extension Board {

	var objects: [Object] {
		let through = stack.top ... stack.bottom
		var objects: [Object] = []

		for (index, trace) in traces.enumerated() where stack.contains(trace.layer) {
			objects.append(Object(
				.segment(trace.start, trace.end, trace.width),
				net: trace.net,
				ref: .trace(index),
				layers: trace.layer ... trace.layer
			))
		}
		for (index, via) in vias.enumerated() {
			objects.append(Object(
				.round(via.at, via.pad),
				net: via.net,
				ref: .via(index),
				layers: via.span
			))
		}
		for (index, footprint) in footprints.enumerated() {
			for pad in footprint.placedPads {
				let layer = footprint.layer(of: pad, in: stack)
				objects.append(Object(
					pad.figure,
					net: pad.net,
					ref: .footprint(index),
					layers: pad.isThrough ? through : layer ... layer
				))
			}
		}
		for (index, hole) in holes.enumerated() {
			objects.append(Object(
				.round(hole.at, hole.diameter),
				net: nil,
				ref: .hole(index),
				layers: through,
				drilled: true
			))
		}
		return objects
	}
}

private extension Design {

	func clashes(among objects: [Object], on layer: Int, clearance: Int) -> [Violation] {
		let here = objects.filter { $0.layers.contains(layer) }
			.sorted { $0.bounds.minX < $1.bounds.minX }
		var found: [Violation] = []

		for (index, object) in here.enumerated() {
			for other in here[(index + 1)...] {
				guard other.bounds.minX - object.bounds.maxX <= clearance else { break }
				guard object.shared(with: other) == layer,
					let violation = clash(object, other, on: layer, clearance: clearance)
				else { continue }
				found.append(violation)
			}
		}
		return found
	}

	func clash(_ a: Object, _ b: Object, on layer: Int, clearance: Int) -> Violation? {
		guard !(a.drilled && b.drilled) else { return nil }
		if !a.drilled, !b.drilled {
			guard let one = a.net, let two = b.net, one != two else { return nil }
		}
		guard a.bounds.outset(clearance).intersects(b.bounds) else { return nil }

		let apart = gap(a.figure, b.figure)
		guard apart < Double(clearance) - 0.5 else { return nil }

		let touching = apart <= 0.5
		let drilled = a.drilled || b.drilled
		let copper = a.drilled ? b : a
		let kind: Violation.Kind = drilled ? .hole : touching ? .short : .clearance

		let text = switch kind {
		case .hole:
			touching
				? "\(label(copper.net)) over a hole"
				: "\(label(copper.net)) \(spacing(apart)) from a hole"
		case .short:
			"\(label(a.net)) meets \(label(b.net))"
		default:
			"\(label(a.net)) \(spacing(apart)) from \(label(b.net))"
		}
		return Violation(
			kind: kind,
			at: meeting(a.figure, b.figure),
			layer: layer,
			refs: [a.ref, b.ref],
			text: text
		)
	}

	func strays(among objects: [Object], clearance: Int) -> [Violation] {
		let bounds = board.bounds

		return objects.compactMap { object in
			let margin = min(
				min(object.bounds.minX - bounds.minX, bounds.maxX - object.bounds.maxX),
				min(object.bounds.minY - bounds.minY, bounds.maxY - object.bounds.maxY)
			)
			guard margin < clearance else { return nil }

			let what = object.drilled ? "A hole" : label(object.net)
			return Violation(
				kind: .edge,
				at: object.bounds.center,
				layer: object.layers.count == 1 ? object.layers.lowerBound : nil,
				refs: [object.ref],
				text: margin <= 0
					? "\(what) over the edge"
					: "\(what) \(spacing(Double(margin))) from the edge"
			)
		}
	}

	func unrouted() -> [Violation] {
		board.ratsnest(planes: planes).map { rat in
			Violation(
				kind: .unrouted,
				at: Pt(x: (rat.from.x + rat.to.x) / 2, y: (rat.from.y + rat.to.y) / 2),
				layer: nil,
				refs: [],
				text: "\(label(rat.net)) not joined"
			)
		}
	}

	func label(_ id: Net.ID?) -> String { net(id)?.name ?? "Copper" }
}

private func spacing(_ nanometers: Double) -> String {
	let mm = nanometers.mm
	return String(format: mm < 0.01 ? "%.3f mm" : "%.2f mm", mm)
}
