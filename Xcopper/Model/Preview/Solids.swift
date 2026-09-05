import Foundation

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

	struct Shape: Equatable {
		var thickness: Nm
		var copper: Bool
		var components: Bool
	}

	var shape: Shape { Shape(thickness: thickness, copper: copper, components: components) }

	var coating: RGBA {
		mask.covers
			? mask.rgb.mixed(with: Palette.bareCopper, 0.18).scaled(1.20)
			: plating.rgb
	}
}

enum Shade: Hashable {
	case mask
	case laminate
	case bore
	case plating
	case coating
	case solder
	case part(RGBA)
}

extension Shade {

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

struct Side {
	var up: Bool
	var z: Double
	var layer: Int
}

extension Side {

	static let core = 0

	var mask: Int { up ? 10 : -10 }
	var copper: Int { up ? 20 : -20 }
	var pads: Int { up ? 25 : -25 }
	var parts: Int { up ? 50 : -50 }

	func lift(_ height: Double) -> Double { up ? z + height : z - height }

	func loop(_ outline: [Pt]) -> [V3] {
		up ? outline.map { $0.v3(z) } : outline.reversed().map { $0.v3(z) }
	}
}

struct Piece {
	var loop: [V3]
	var holes: [[V3]]
	var normal: V3
	var shade: Shade
	var level: Int
}

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

	func standing(on underside: Bool) -> Double {
		footprints
			.filter { footprint in footprint.flipped == underside && footprint.package.stands }
			.map { footprint in Double(footprint.package.height + footprint.package.standoff).mm }
			.max() ?? 0.0
	}

	private var barrels: [(figure: Figure, plated: Bool)] {
		vias.map { via in (Figure.round(via.at, via.drill), true) }
			+ footprints.flatMap { footprint in
				footprint.placedPads
					.filter(\.isThrough)
					.map { pad in (Figure.round(pad.at, pad.drill), true) }
			}
			+ holes.map { hole in (Figure.round(hole.at, hole.diameter), false) }
	}

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

	private func stuff(
		_ footprint: Footprint,
		side: Side,
		far: Side,
		into model: inout Model
	) {
		let package = footprint.package
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
