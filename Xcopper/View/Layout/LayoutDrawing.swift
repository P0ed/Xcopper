import AppKit
import SwiftUI

@MainActor
struct LayoutDrawing {
	var model = Model()

	mutating func fill(_ figure: Figure, color: Color, level: Int, cutouts: [Figure] = []) {
		guard hasArea(figure) else { return }
		let outline = figure.polygon()
		let holes = cutouts.filter {
			hasArea($0) && $0.bounds.intersects(figure.bounds)
		}.map { $0.polygon() }
		if holes.allSatisfy({ holds(outline, $0) }) {
			add(outline, holes: holes, color: color, level: level)
		} else {
			for loop in punched(outline, by: holes) { add(loop, color: color, level: level) }
		}
	}

	mutating func outline(_ figure: Figure, width: µm, color: Color, level: Int) {
		fill(figure.outset(width / 2), color: color, level: level, cutouts: [figure.outset(-width / 2)])
	}

	mutating func stroke(
		_ points: [Point],
		closed: Bool = false,
		width: µm,
		color: Color,
		level: Int,
		dash: µm = 0
	) {
		guard points.count >= 2 else { return }
		let points = closed ? points + [points[0]] : points
		for (a, b) in zip(points, points.dropFirst()) {
			let from = a.v3(0.0)
			let to = b.v3(0.0)
			let delta = to - from
			let length = delta.length
			guard length > 0.0 else { continue }
			let direction = delta * (1.0 / length)
			let side = V3(x: -direction.y, y: direction.x, z: 0.0) * (Double.mm(width) / 2.0)
			let step = dash > 0 ? Double.mm(dash) : length
			for start in stride(from: 0.0, to: length, by: step * 2.0) {
				let a = from + direction * start
				let b = from + direction * min(start + step, length)
				model.add([a - side, b - side, b + side, a + side], shade: shade(color), level: level)
			}
		}
	}

	private mutating func add(_ outline: [Point], holes: [[Point]] = [], color: Color, level: Int) {
		model.add(
			outline.map { $0.v3(0.0) },
			holes: holes.map { $0.map { $0.v3(0.0) } },
			shade: shade(color),
			level: level
		)
	}

	private func hasArea(_ figure: Figure) -> Bool {
		switch figure {
		case let .rect(rect): rect.size.width > 0 && rect.size.height > 0
		case let .round(_, diameter), let .segment(_, _, diameter): diameter > 0
		}
	}

	private func shade(_ color: Color) -> Shade {
		let color = NSColor(color).usingColorSpace(.sRGB) ?? .white
		return .part(RGBA(
			r: color.redComponent,
			g: color.greenComponent,
			b: color.blueComponent,
			a: color.alphaComponent
		))
	}
}
