import Foundation

/// What the board is made of and how much of it to show
struct Finish: Equatable {
	var mask: Mask = .green
	var plating: Plating = .gold
	var thickness: Nm = .thicknesses[1]
	var copper = true
	var components = true
}

extension Nm {
	static var thicknesses: [Nm] { [.mm(0.8), .mm(1.6), .mm(2.0)] }
}

extension Finish {

	/// What shapes the model, as against what paints it. A face is cut into
	/// triangles once and stands for every colour of mask afterwards, so only a
	/// change in these sends the board back to be built again.
	struct Shape: Equatable {
		var thickness: Nm
		var copper: Bool
		var components: Bool
	}

	var shape: Shape { Shape(thickness: thickness, copper: copper, components: components) }

	/// How the copper between the pads reads. Under a coloured mask it is the
	/// same coating lifted and warmed by what lies beneath, which is how a
	/// trace shows through a finished board. A clear mask covers nothing, so
	/// the copper it leaves open is plated along with the pads and the whole
	/// face comes back gold.
	var coating: RGBA {
		mask.covers
			? mask.rgb.mixed(with: Palette.bareCopper, 0.18).scaled(1.20)
			: plating.rgb
	}
}

/// What a face is painted in, named rather than mixed. The board is cut into
/// triangles without ever asking what colour it comes back, so the mask and the
/// plating can be changed over a model already built.
enum Shade: Hashable {
	/// The solder mask lying over a face
	case mask
	/// Bare laminate, which the cut edge shows
	case laminate
	/// The wall of a hole the fab leaves unplated
	case bore
	/// Whatever the fab plates open copper with
	case plating
	/// Copper reading up through whatever covers it
	case coating
	/// Solder, over a lead or on the tail of a pin
	case solder
	/// A part's own moulding, which the library settles rather than the fab
	case part(RGBA)
}

extension Shade {

	/// What this comes back as, once the fab is told what to make the board of
	func rgb(_ finish: Finish) -> RGBA {
		switch self {
		case .mask: finish.mask.rgb
		case .laminate: Palette.laminate
		case .bore: Palette.laminate.scaled(0.55)
		case .plating: finish.plating.rgb
		case .coating: finish.coating
		case .solder: Palette.solder
		case let .part(color): color
		}
	}
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

	/// Where a thing sits in the stack, counted out from the laminate and
	/// signed by the side it belongs to. Everything on one level lies at one
	/// height, and a level stands a hair clear of the one under it, so the
	/// copper never fights the substrate it is laid on.
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

/// One flat face of the model, waiting to be cut into triangles
struct Piece {
	var loop: [V3]
	/// Punched out of the loop, so that a drill reads through the face
	var holes: [[V3]]
	var normal: V3
	var shade: Shade
	var level: Int
}

/// The board as something to look at
struct Model {
	var pieces: [Piece] = []
}

extension Model {

	mutating func add(_ loop: [V3], holes: [[V3]] = [], shade: Shade, level: Int) {
		guard loop.count >= 3 else { return }
		pieces.append(Piece(
			loop: loop,
			holes: holes,
			normal: loop.normal,
			shade: shade,
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
		shade: Shade,
		level: Int,
		capped: Bool = true
	) {
		guard outline.count >= 3, from != to else { return }
		let upper = max(from, to)
		let lower = min(from, to)

		for index in outline.indices {
			let a = outline[index]
			let b = outline[(index + 1) % outline.count]
			add([a.v3(upper), a.v3(lower), b.v3(lower), b.v3(upper)], shade: shade, level: level)
		}
		guard capped else { return }
		add((to > from ? outline : outline.reversed()).map { $0.v3(to) }, shade: shade, level: level)
	}

	/// A ring of quads between two circles, how a rounded tip is built up
	mutating func add(
		band lower: [Pt],
		at lowerZ: Double,
		to upper: [Pt],
		at upperZ: Double,
		shade: Shade,
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
				shade: shade,
				level: level
			)
		}
	}
}

extension Board {

	/// Everything the preview draws: the substrate, the copper the fab puts on
	/// both faces of it, and the parts the schematic asked to be stuffed into
	/// it. No legend, because the fabrication set carries none.
	func model(_ shape: Finish.Shape) -> Model {
		let thickness = Double(shape.thickness).mm
		let top = Side(up: true, z: 0.0, layer: stack.top)
		let bottom = Side(up: false, z: -thickness, layer: stack.bottom)

		var model = Model()
		substrate(into: &model, top: top, bottom: bottom)

		if shape.copper {
			for side in [top, bottom] {
				copper(into: &model, side: side)
			}
		}
		if shape.components {
			parts(into: &model, top: top, bottom: bottom)
		}
		return model
	}

	/// How far the tallest part on one side of the board stands off it
	func standing(on underside: Bool) -> Double {
		footprints
			.filter { footprint in footprint.flipped == underside && footprint.package.stands }
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
	private func substrate(into model: inout Model, top: Side, bottom: Side) {
		let outline = bounds.corners
		let punched = drills.map { drill in drill.polygon() }

		for side in [top, bottom] {
			model.add(
				side.loop(outline),
				holes: punched.map { hole in side.loop(hole) },
				shade: .mask,
				level: side.mask
			)
		}
		model.add(
			prism: outline,
			from: bottom.z,
			to: top.z,
			shade: .laminate,
			level: Side.core,
			capped: false
		)
		for (figure, plated) in barrels {
			model.add(
				prism: Array(figure.polygon().reversed()),
				from: top.z,
				to: bottom.z,
				shade: plated ? .plating : .bore,
				level: Side.core,
				capped: false
			)
		}
	}

	/// The outer layer: traces and tented vias reading through whatever covers
	/// them, and the pads the mask leaves open. Every drill on the board is
	/// punched through the lot of it, since a hole is made after the copper is
	/// laid and takes back whatever stood over it.
	private func copper(into model: inout Model, side: Side) {
		let punches = drills.map { drill in (bounds: drill.bounds, loop: drill.polygon()) }

		for trace in traces where trace.layer == side.layer {
			lay(
				.segment(trace.start, trace.end, trace.width),
				arc: 2,
				drills: punches,
				shade: .coating,
				level: side.copper,
				side: side,
				into: &model
			)
		}
		for via in vias where via.spans(side.layer) {
			lay(
				.round(via.at, via.pad),
				drills: punches,
				shade: .coating,
				level: side.copper,
				side: side,
				into: &model
			)
		}
		for pad in pads(on: side.layer) {
			lay(
				pad.figure,
				drills: punches,
				shade: .plating,
				level: side.pads,
				side: side,
				into: &model
			)
		}
	}

	/// One piece of copper laid on a face, cut back to the drills that reach
	/// it. A drill the copper closes right round is a hole read through the one
	/// face, the way a pad reads through its own barrel; a drill reaching over
	/// the edge of the copper — a trace running onto a pad, or the ring of a
	/// panel jack overlapping the wire hole beside it — takes a piece of that
	/// copper away instead, and what is left of it comes back in pieces.
	private func lay(
		_ figure: Figure,
		arc: Int? = nil,
		drills: [(bounds: Rect, loop: [Pt])],
		shade: Shade,
		level: Int,
		side: Side,
		into model: inout Model
	) {
		let outline = figure.polygon(arc: arc)
		let reaching = drills.filter { drill in drill.bounds.intersects(figure.bounds) }.map(\.loop)

		guard reaching.allSatisfy({ drill in holds(outline, drill) }) else {
			for piece in punched(outline, by: reaching) {
				model.add(side.loop(piece), shade: shade, level: level)
			}
			return
		}
		model.add(
			side.loop(outline),
			holes: reaching.map { hole in side.loop(hole) },
			shade: shade,
			level: level
		)
	}

	private func parts(into model: inout Model, top: Side, bottom: Side) {
		for footprint in footprints {
			stuff(
				footprint,
				side: footprint.flipped ? bottom : top,
				far: footprint.flipped ? top : bottom,
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
		into model: inout Model
	) {
		let package = footprint.package
		// A part the board only carries the pads of is held somewhere else, so
		// there is nothing of it to raise: no body, no leads and no tails
		guard package.stands else { return }

		let standoff = Double(package.standoff).mm
		let height = Double(package.height).mm
		let placed = footprint.placedPads

		if package.leads {
			for pad in placed where !pad.isThrough {
				model.add(
					prism: pad.leg.polygon(arc: 2),
					from: side.z,
					to: side.lift(standoff + 0.12),
					shade: .solder,
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
					shade: .plating,
					level: side.parts
				)
			}
			// The tail, clipped off just proud of the far face
			model.add(
				prism: post,
				from: far.z,
				to: far.lift(1.0),
				shade: .solder,
				level: far.parts
			)
		}

		let base = side.lift(standoff)
		let top = side.lift(standoff + height)
		let center = footprint.placedBody.center

		switch package.shell {
		case .none:
			break
		case .block:
			model.add(
				prism: footprint.placedBody.outset(-Int(package.inset)).corners,
				from: base,
				to: top,
				shade: .part(package.color),
				level: side.parts
			)
		case let .can(diameter):
			model.add(
				prism: circle(at: center, diameter: Int(diameter), arc: 4),
				from: base,
				to: top,
				shade: .part(package.color),
				level: side.parts
			)
		case let .dome(diameter):
			dome(
				at: center,
				diameter: Int(diameter),
				from: base,
				height: height,
				shade: .part(package.color),
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
		shade: Shade,
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
			shade: shade,
			level: side.parts,
			capped: false
		)
		for band in 1 ... bands {
			let angle = Double(band) / Double(bands) * .pi / 2.0
			let next = circle(at: center, diameter: Int(Double(diameter) * cos(angle)), arc: 4)
			let nextZ = shoulderZ + (side.up ? 1.0 : -1.0) * radius * sin(angle)
			model.add(band: ring, at: ringZ, to: next, at: nextZ, shade: shade, level: side.parts)
			ring = next
			ringZ = nextZ
		}
	}
}
