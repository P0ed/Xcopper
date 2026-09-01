import Foundation

/// Something the board does that a fab cannot make, or something the schematic
/// asks for that the copper does not do. Read straight back out of the drawing
/// the way the netlist and the ratsnest are — nothing is stored, so a
/// violation cannot outlive what caused it.
struct Violation: Hashable {

	enum Kind: Int, Hashable, Comparable {
		/// Copper of two nets touching
		case short
		/// Copper of two nets closer than the rule
		case clearance
		/// Copper too near a hole drilled through the board
		case hole
		/// Copper over the cut edge, or too near it
		case edge
		/// A connection the netlist asks for that no copper makes
		case unrouted

		static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }
	}

	var kind: Kind
	/// Where to look: the spot the layout marks and scrolls to
	var at: Pt
	/// The copper layer it stands on, none for a fault that is on no one layer
	var layer: Int?
	/// What a click on it picks up
	var refs: Set<Ref>
	/// What it says of itself
	var text: String
}

extension Violation {

	/// Worst first, and the same order every time, so a list of them does not
	/// shuffle under the pointer
	static func order(_ lhs: Violation, _ rhs: Violation) -> Bool {
		lhs.kind != rhs.kind ? lhs.kind < rhs.kind : Pt.order(lhs.at, rhs.at)
	}
}

extension Design {

	/// Everything wrong with the board: what a fab would balk at, and what the
	/// schematic asks for that the copper does not yet do.
	func check() -> [Violation] {
		(faults() + unrouted()).sorted(by: Violation.order)
	}

	/// The faults that stand somewhere on the copper, which is where the layout
	/// marks them. What is unrouted is left out: the ratsnest draws that
	/// already.
	func faults() -> [Violation] {
		let clearance = Int(board.rules.clearance)
		let objects = board.objects

		return board.stack.copper.flatMap { layer in
			clashes(among: objects, on: layer, clearance: clearance)
		} + strays(among: objects, clearance: clearance)
	}
}

/// One thing the checker measures: a length of copper, a pad, a via, or a hole
/// drilled through the lot of them
private struct Object {
	var figure: Figure
	var net: Net.ID?
	var ref: Ref
	/// The copper layers it reaches, which is every one of them for a through
	/// pad, a via barrel or a hole
	var layers: ClosedRange<Int>
	/// A hole, which carries no net and which nothing may come near
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

	/// The one layer a pair is measured on: the first both of them reach, so a
	/// through pad beside another is reported once rather than once a layer
	func shared(with other: Object) -> Int? {
		let layer = max(layers.lowerBound, other.layers.lowerBound)
		return layers.contains(layer) && other.layers.contains(layer) ? layer : nil
	}
}

private extension Board {

	/// Everything on the board that has to keep its distance, each thing once,
	/// with the layers it reaches
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

	/// What one layer carries, measured against itself. Sorted by where each
	/// object starts, so the scan stops as soon as the next one is out of
	/// reach: a board costs about what is drawn on it rather than the square
	/// of it.
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

	/// How two objects of one layer get on. Copper is only judged against
	/// copper the design has named and named differently: unnamed copper is
	/// copper the design says nothing about, and a net is allowed to touch
	/// itself. A hole is nobody's net and everything has to stand clear of it.
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

	/// Everything that has wandered over the cut edge or come too near it. A
	/// figure reaches exactly as far as its bounds on every side, so the four
	/// margins are the whole of the measurement.
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

	/// Connections the netlist asks for that no copper makes. The ratsnest
	/// draws them already; counting them here is what stops an unrouted board
	/// being sent to a fab without a word.
	func unrouted() -> [Violation] {
		board.ratsnest().map { rat in
			Violation(
				kind: .unrouted,
				at: Pt(x: (rat.from.x + rat.to.x) / 2, y: (rat.from.y + rat.to.y) / 2),
				layer: nil,
				refs: [],
				text: "\(label(rat.net)) not joined"
			)
		}
	}

	/// What a net is called in a violation. Copper the design has not named is
	/// just copper.
	func label(_ id: Net.ID?) -> String { net(id)?.name ?? "Copper" }
}

/// A gap as a violation reads it out, in the millimeters the board is drawn in
private func spacing(_ nanometers: Double) -> String {
	let mm = nanometers.mm
	return String(format: mm < 0.01 ? "%.3f mm" : "%.2f mm", mm)
}
