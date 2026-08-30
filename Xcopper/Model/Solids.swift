import Foundation

/// What the board is made of and how much of it to show
struct Finish: Equatable {
	var mask: Mask = .green
	var plating: Plating = .gold
	var thickness: Nm = .mm(1.6)
	var copper = true
	var components = true
}

extension Nm {

	static var thicknesses: [Nm] { [.mm(0.8), .mm(1.0), .mm(1.6), .mm(2.0)] }
}

/// One face of the board and everything that belongs to it. Both sides are
/// built by the same code, which only has to know which way is out.
struct Side {
	var up: Bool
	/// Height of the surface, board space
	var z: Double
	/// The copper layer on this face
	var layer: Int
}

extension Side {

	/// Painting order, the bottom of the board first. Everything sitting at
	/// one height forms a group of its own, so copper never fights with the
	/// substrate it lies on: only what shares a level is sorted by distance.
	static let core = 0

	var mask: Int { up ? 10 : -10 }
	var copper: Int { up ? 20 : -20 }
	var pads: Int { up ? 25 : -25 }
	var parts: Int { up ? 50 : -50 }

	/// `height` above the surface, whichever way this face points
	func lift(_ height: Double) -> Double { up ? z + height : z - height }

	/// A loop lying on this face, wound so that it looks out of the board
	func loop(_ outline: [Pt]) -> [V3] {
		up ? outline.map { $0.v3(z) } : outline.reversed().map { $0.v3(z) }
	}
}

/// One flat polygon of the model, waiting for a camera to say where it lands
struct Piece {
	var loop: [V3]
	/// Punched out of the loop, so what was painted under it reads through
	var holes: [[V3]]
	var normal: V3
	/// Where it sits, for ordering it against the rest of its level
	var at: V3
	var color: Rgb
	var level: Int
}

/// The board as something to look at
struct Model {
	var pieces: [Piece] = []
}

extension Model {

	mutating func add(_ loop: [V3], holes: [[V3]] = [], color: Rgb, level: Int) {
		guard loop.count >= 3 else { return }
		pieces.append(Piece(
			loop: loop,
			holes: holes,
			normal: loop.normal,
			at: loop.centroid,
			color: color,
			level: level
		))
	}

	/// A solid raised over `outline` between two heights: the walls of it and,
	/// unless it is left open, the face closing the far end. `outline` is wound
	/// the way the layout draws it, which puts the walls' front on the outside;
	/// hand it the loop backwards for a hole, whose inside is what shows.
	mutating func add(
		prism outline: [Pt],
		from: Double,
		to: Double,
		color: Rgb,
		level: Int,
		capped: Bool = true
	) {
		guard outline.count >= 3, from != to else { return }
		let upper = max(from, to)
		let lower = min(from, to)

		for index in outline.indices {
			let a = outline[index]
			let b = outline[(index + 1) % outline.count]
			add([a.v3(upper), a.v3(lower), b.v3(lower), b.v3(upper)], color: color, level: level)
		}
		guard capped else { return }
		add((to > from ? outline : outline.reversed()).map { $0.v3(to) }, color: color, level: level)
	}

	/// A ring of quads between two circles, how a rounded tip is built up
	mutating func add(
		band lower: [Pt],
		at lowerZ: Double,
		to upper: [Pt],
		at upperZ: Double,
		color: Rgb,
		level: Int
	) {
		guard lower.count == upper.count, lower.count >= 3, lowerZ != upperZ else { return }
		let ascending = lowerZ < upperZ
		let low = ascending ? lower : upper
		let high = ascending ? upper : lower
		let lowZ = min(lowerZ, upperZ)
		let highZ = max(lowerZ, upperZ)

		for index in low.indices {
			let next = (index + 1) % low.count
			add(
				[
					high[index].v3(highZ),
					low[index].v3(lowZ),
					low[next].v3(lowZ),
					high[next].v3(highZ),
				],
				color: color,
				level: level
			)
		}
	}
}

extension Board {

	/// Everything the preview draws: the substrate, the copper the fab puts on
	/// both faces of it, and the parts the schematic asked to be stuffed into
	/// it. No legend, because the fabrication set carries none.
	func model(finish: Finish) -> Model {
		let thickness = Double(finish.thickness).mm
		let top = Side(up: true, z: 0.0, layer: stack.top)
		let bottom = Side(up: false, z: -thickness, layer: stack.bottom)

		var model = Model()
		substrate(into: &model, finish: finish, top: top, bottom: bottom)

		if finish.copper {
			for side in [top, bottom] {
				copper(into: &model, finish: finish, side: side)
			}
		}
		if finish.components {
			parts(into: &model, finish: finish, top: top, bottom: bottom)
		}
		return model
	}

	/// How far the tallest part on one side of the board stands off it
	func standing(on underside: Bool) -> Double {
		footprints
			.filter { footprint in footprint.flipped == underside }
			.map { footprint in Double(footprint.package.height + footprint.package.standoff).mm }
			.max() ?? 0.0
	}

	/// Every hole through the board, and whether it is lined with copper
	private var barrels: [(figure: Figure, plated: Bool)] {
		vias.map { via in (Figure.round(via.at, via.drill), true) }
			+ footprints.flatMap { footprint in
				footprint.placedPads
					.filter(\.isThrough)
					.map { pad in (Figure.round(pad.at, pad.drill), true) }
			}
			+ holes.map { hole in (Figure.round(hole.at, hole.diameter), false) }
	}

	/// The laminate: two masked faces, the cut edge around them and the wall of
	/// every hole punched through
	private func substrate(into model: inout Model, finish: Finish, top: Side, bottom: Side) {
		let outline = bounds.corners
		let punched = drills.map { drill in drill.polygon() }

		for side in [top, bottom] {
			model.add(
				side.loop(outline),
				holes: punched.map { hole in side.loop(hole) },
				color: finish.mask.rgb,
				level: side.mask
			)
		}
		model.add(
			prism: outline,
			from: bottom.z,
			to: top.z,
			color: Palette.laminate,
			level: Side.core,
			capped: false
		)
		for (figure, plated) in barrels {
			model.add(
				prism: Array(figure.polygon().reversed()),
				from: top.z,
				to: bottom.z,
				color: plated ? finish.plating.rgb : Palette.laminate.scaled(0.55),
				level: Side.core,
				capped: false
			)
		}
	}

	/// The outer layer: traces and tented vias reading through the mask, and
	/// the pads it leaves open
	private func copper(into model: inout Model, finish: Finish, side: Side) {
		// Mask over copper is the same coating lifted and warmed by what is
		// under it, which is how a trace shows through a finished board
		let coated = finish.mask.rgb.mixed(with: Palette.bareCopper, 0.18).scaled(1.20)

		for trace in traces where trace.layer == side.layer {
			model.add(
				side.loop(Figure.segment(trace.start, trace.end, trace.width).polygon(arc: 2)),
				color: coated,
				level: side.copper
			)
		}
		for via in vias where via.spans(side.layer) {
			model.add(
				side.loop(Figure.round(via.at, via.pad).polygon()),
				holes: [side.loop(circle(at: via.at, diameter: Int(via.drill)))],
				color: coated,
				level: side.copper
			)
		}
		for pad in pads(on: side.layer) {
			model.add(
				side.loop(pad.figure.polygon()),
				holes: pad.isThrough ? [side.loop(circle(at: pad.at, diameter: Int(pad.drill)))] : [],
				color: finish.plating.rgb,
				level: side.pads
			)
		}
	}

	private func parts(into model: inout Model, finish: Finish, top: Side, bottom: Side) {
		for footprint in footprints {
			stuff(
				footprint,
				side: footprint.flipped ? bottom : top,
				far: footprint.flipped ? top : bottom,
				finish: finish,
				into: &model
			)
		}
	}

	/// One part standing on the board: what holds it up, what comes through to
	/// the other side, and the body itself
	private func stuff(
		_ footprint: Footprint,
		side: Side,
		far: Side,
		finish: Finish,
		into model: inout Model
	) {
		let package = footprint.package
		let standoff = Double(package.standoff).mm
		let height = Double(package.height).mm
		let placed = footprint.placedPads

		if package.leads {
			for pad in placed where !pad.isThrough {
				model.add(
					prism: pad.figure.polygon(arc: 2),
					from: side.z,
					to: side.lift(standoff + 0.12),
					color: Palette.solder,
					level: side.parts
				)
			}
		}
		for pad in placed where pad.isThrough {
			let width = max(Int(Nm.mm(0.4)), Int(Double(pad.drill) * 0.7))
			let post = Rect(center: pad.at, size: Size(width: width, height: width)).corners
			if package.posts {
				model.add(
					prism: post,
					from: side.z,
					to: side.lift(height + 6.0),
					color: finish.plating.rgb,
					level: side.parts
				)
			}
			// The tail, clipped off just proud of the far face
			model.add(
				prism: post,
				from: far.z,
				to: far.lift(1.0),
				color: Palette.solder,
				level: far.parts
			)
		}

		let base = side.lift(standoff)
		let top = side.lift(standoff + height)
		let center = footprint.placedBody.center

		switch package.shell {
		case .block:
			model.add(
				prism: footprint.placedBody.outset(-Int(package.inset)).corners,
				from: base,
				to: top,
				color: package.color,
				level: side.parts
			)
		case let .can(diameter):
			model.add(
				prism: circle(at: center, diameter: Int(diameter), arc: 4),
				from: base,
				to: top,
				color: package.color,
				level: side.parts
			)
		case let .dome(diameter):
			dome(
				at: center,
				diameter: Int(diameter),
				from: base,
				height: height,
				color: package.color,
				side: side,
				into: &model
			)
		}
	}

	/// A cylinder closed by a rounded tip, the shape of an indicator
	private func dome(
		at center: Pt,
		diameter: Int,
		from base: Double,
		height: Double,
		color: Rgb,
		side: Side,
		into model: inout Model
	) {
		let radius = Double(diameter).mm / 2.0
		let shoulder = max(0.0, height - radius)
		let bands = 4
		let shoulderZ = side.up ? base + shoulder : base - shoulder
		var ring = circle(at: center, diameter: diameter, arc: 4)
		var ringZ = shoulderZ

		model.add(
			prism: ring,
			from: base,
			to: shoulderZ,
			color: color,
			level: side.parts,
			capped: false
		)
		for band in 1 ... bands {
			let angle = Double(band) / Double(bands) * .pi / 2.0
			let next = circle(at: center, diameter: Int(Double(diameter) * cos(angle)), arc: 4)
			let nextZ = shoulderZ + (side.up ? 1.0 : -1.0) * radius * sin(angle)
			model.add(band: ring, at: ringZ, to: next, at: nextZ, color: color, level: side.parts)
			ring = next
			ringZ = nextZ
		}
	}
}
