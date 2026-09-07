import Foundation

struct Flag: Hashable, Codable {
	var at: Point
	var rotation: Rotation
	var net: String
	var kind: Kind
}

extension Flag {

	enum Kind: String, Codable, CaseIterable {
		case power, ground

		var name: String { self == .power ? "Power" : "Ground" }
		var defaultNet: String { self == .power ? "VCC" : "GND" }
	}

	struct Spec: Hashable, Codable {
		var kind: Kind = .power
		var net: String = ""

		var summary: String { "\(kind.name) \(net.isEmpty ? kind.defaultNet : net)" }
	}

	init(spec: Spec, at: Point) {
		self.at = at
		rotation = .r0
		kind = spec.kind
		net = spec.net.isEmpty ? spec.kind.defaultNet : spec.net
	}

	var root: Point {
		place(Point(x: 0, y: kind == .power ? -.mm(2.54) : .mm(2.54)))
	}

	var figure: Figure { .segment(at, root, .mm(0.2)) }

	var body: Rect {
		let stem = Int.mm(2.54)
		return switch kind {
		case .power:
			Rect(center: Point(x: 0, y: -stem / 2), size: Size(width: .mm(2.54), height: stem))
		case .ground:
			Rect(center: Point(x: 0, y: .mm(1.905)), size: Size(width: .mm(3.81), height: .mm(3.81)))
		}
	}

	var glyph: [Glyph] {
		let stem = Int.mm(2.54)
		switch kind {
		case .power:
			let bar = Int.mm(1.27)
			return [.path([Point(x: -bar, y: -stem), Point(x: bar, y: -stem)], closed: false, filled: false)]
		case .ground:
			let step = Int.mm(0.635)
			return (0 ..< 3).map { row in
				let half = Int.mm(1.905) - row * step
				let y = stem + row * step
				return .path([Point(x: -half, y: y), Point(x: half, y: y)], closed: false, filled: false)
			}
		}
	}

	func place(_ local: Point) -> Point { local.rotated(rotation) + at }

	var placedBody: Rect {
		Rect(center: place(body.center), size: rotation.isQuarter ? body.size.swapped : body.size)
	}

	var placedGlyph: [Glyph] {
		glyph.map { $0.placed(place, quarter: rotation.isQuarter) }
	}

	var placedExtent: Rect {
		Rect.union([placedBody, figure.bounds] + placedGlyph.map(\.bounds)) ?? placedBody
	}
}
