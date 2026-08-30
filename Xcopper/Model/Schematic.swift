/// Symbol pin. `at` is the connection point at the tip of the leg, `direction`
/// points outward from the body along `Pt(x: 1, y: 0).rotated(direction)`.
struct Pin: Hashable, Codable {
	var at: Pt
	var direction: Rotation
	var length: Nm
	var name: String
	var number: String
}

/// Symbol outline primitive, stroked rather than filled like `Figure`
enum Glyph: Hashable, Codable {
	case path([Pt], closed: Bool, filled: Bool)
	case rect(Rect)
	case circle(Pt, Nm)
}

struct Symbol: Hashable, Codable {
	var reference: String
	var value: String
	var at: Pt
	var rotation: Rotation
	var mirrored: Bool
	var kind: Kind
	var pins: [Pin]
	var body: Rect
	var glyph: [Glyph]
}

struct Wire: Hashable, Codable {
	var start: Pt
	var end: Pt
}

/// Names the net it is anchored to. Drawn horizontally, above `at`.
struct NetLabel: Hashable, Codable {
	var at: Pt
	var text: String
}

struct Schematic: Equatable, Codable {
	var size: Size
	var symbols: [Symbol]
	var wires: [Wire]
	var labels: [NetLabel]
}

extension Schematic {

	/// Reference to an object stored in a `Schematic` collection
	enum Ref: Hashable, Codable {
		case symbol(Int)
		case wire(Int)
		case label(Int)

		var index: Int {
			switch self {
			case let .symbol(index), let .wire(index), let .label(index): index
			}
		}

		static func order(_ lhs: Ref, _ rhs: Ref) -> Bool { lhs.index < rhs.index }
	}

	init(size: Size = .init(width: .mm(297), height: .mm(210))) {
		self.size = size
		symbols = []
		wires = []
		labels = []
	}

	var bounds: Rect { Rect(origin: .zero, size: size) }
}

extension Pin {

	/// Where the leg meets the body
	var root: Pt { at + Pt(x: -Int(length), y: 0).rotated(direction) }

	var figure: Figure { .segment(at, root, .mm(0.2)) }
}

extension Wire {
	var figure: Figure { .segment(start, end, .mm(0.2)) }
}

extension NetLabel {

	static let height = Int.mm(1.8)

	/// Nominal extent, for hit testing and selection
	var bounds: Rect {
		Rect(
			origin: Pt(x: at.x, y: at.y - Self.height),
			size: Size(width: max(1, text.count) * .mm(1.1) + .mm(0.8), height: Self.height)
		)
	}
}

extension Glyph {

	func placed(_ transform: (Pt) -> Pt, quarter: Bool) -> Glyph {
		switch self {
		case let .path(points, closed, filled):
			.path(points.map(transform), closed: closed, filled: filled)
		case let .rect(rect):
			.rect(Rect(center: transform(rect.center), size: quarter ? rect.size.swapped : rect.size))
		case let .circle(center, diameter):
			.circle(transform(center), diameter)
		}
	}

	var bounds: Rect {
		switch self {
		case let .path(points, _, _):
			Rect.union(points.map { point in Rect(origin: point, size: .zero) }) ?? .init(origin: .zero, size: .zero)
		case let .rect(rect):
			rect
		case let .circle(center, diameter):
			Rect(center: center, size: Size(width: Int(diameter), height: Int(diameter)))
		}
	}
}

extension Symbol {

	/// Pins in sheet coordinates, with mirroring and rotation applied
	var placedPins: [Pin] {
		pins.map { pin in
			modifying(pin) { pin in
				pin.direction = direction(of: pin.direction)
				pin.at = place(pin.at)
			}
		}
	}

	/// Body outline in sheet coordinates
	var placedBody: Rect {
		Rect(
			center: place(body.center),
			size: rotation.isQuarter ? body.size.swapped : body.size
		)
	}

	var placedGlyph: [Glyph] {
		glyph.map { shape in shape.placed(place, quarter: rotation.isQuarter) }
	}

	func place(_ local: Pt) -> Pt {
		(mirrored ? local.mirroredX : local).rotated(rotation) + at
	}

	func direction(of local: Rotation) -> Rotation {
		(mirrored ? local.mirroredX : local).adding(rotation)
	}

	/// Body and glyph together, so text can be placed clear of the drawing
	var placedExtent: Rect {
		Rect.union([placedBody] + placedGlyph.map(\.bounds)) ?? placedBody
	}

	/// Net this symbol forces onto whatever it touches, for power and ground flags
	var suppliedNet: String? {
		kind.isPower && !value.isEmpty ? value : nil
	}
}
