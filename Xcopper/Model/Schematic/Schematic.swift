import Foundation

struct Pin: Hashable, Codable {
	var at: Point
	var direction: Rotation
	var length: Nm
	var name: String
	var number: String
}

enum PinText {
	static let nameHeight = Int.mm(1.27)
	static let numberHeight = Int.mm(1.016)
	static let inset = Int.mm(0.762)
	static let gap = Int.mm(0.254)
	static let advance = 0.62

	static func width(_ text: String, height: Int = nameHeight) -> Int {
		Int((Double(text.count) * Double(height) * advance).rounded())
	}
}

enum Glyph: Hashable, Codable {
	case path([Point], closed: Bool, filled: Bool)
	case rect(Rect)
	case circle(Point, Nm)
}

struct Symbol: Hashable, Codable {
	var reference: String
	var value: String
	var at: Point
	var rotation: Rotation
	var mirrored: Bool
	var kind: Kind
	var pins: [Pin]
	var body: Rect
	var glyph: [Glyph]
	var component: Component?
}

struct Wire: Hashable, Codable {
	var start: Point
	var end: Point
}

struct NetLabel: Hashable, Codable {
	var at: Point
	var text: String
}

struct Schematic: Equatable, Codable {
	var size: Size
	var symbols: [Symbol]
	var flags: [Flag]
	var wires: [Wire]
	var labels: [NetLabel]
}

extension Schematic {

	enum Ref: Hashable, Codable {
		case module(UUID)
		case symbol(Int)
		case flag(Int)
		case wire(Int)
		case label(Int)

		enum Kind: Hashable { case module, symbol, flag, wire, label }

		var kind: Kind {
			switch self {
			case .module: .module
			case .symbol: .symbol
			case .flag: .flag
			case .wire: .wire
			case .label: .label
			}
		}

		var index: Int {
			switch self {
			case .module: Int.max
			case let .symbol(index), let .flag(index), let .wire(index), let .label(index): index
			}
		}

		static func order(_ lhs: Ref, _ rhs: Ref) -> Bool { lhs.index < rhs.index }
	}

	init(size: Size = .init(width: .mm(297), height: .mm(210))) {
		self.size = size
		symbols = []
		flags = []
		wires = []
		labels = []
	}

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		size = try values.decode(Size.self, forKey: .size)
		symbols = []
		flags = try values.decodeIfPresent([Flag].self, forKey: .flags) ?? []
		for element in try values.decode([SymbolOrFlag].self, forKey: .symbols) {
			switch element {
			case let .symbol(symbol): symbols.append(symbol)
			case let .flag(flag): flags.append(flag)
			}
		}
		wires = try values.decode([Wire].self, forKey: .wires)
		labels = try values.decode([NetLabel].self, forKey: .labels)
	}

	private enum SymbolOrFlag: Decodable {
		case symbol(Symbol), flag(Flag)

		private enum CodingKeys: String, CodingKey { case kind, at, rotation, value }

		init(from decoder: Decoder) throws {
			let values = try decoder.container(keyedBy: CodingKeys.self)
			if let kind = Flag.Kind(rawValue: try values.decode(String.self, forKey: .kind)) {
				self = .flag(Flag(
					at: try values.decode(Point.self, forKey: .at),
					rotation: try values.decode(Rotation.self, forKey: .rotation),
					net: try values.decode(String.self, forKey: .value),
					kind: kind
				))
			} else {
				self = .symbol(try Symbol(from: decoder))
			}
		}
	}

	var bounds: Rect { Rect(origin: .zero, size: size) }

	mutating func resize(size: Size) {
		self.size = size
	}
}

extension Pin {

	var root: Point { at + Point(x: -Int(length), y: 0).rotated(direction) }

	var figure: Figure { .segment(at, root, .mm(0.2)) }

	var isNamed: Bool { !name.isEmpty && name != number }
}

extension Wire {
	var figure: Figure { .segment(start, end, .mm(0.2)) }
}

extension NetLabel {

	static let height = Int.mm(1.8)
	static let anchor = Int.mm(0.5)

	var bounds: Rect {
		Rect(
			origin: Point(x: at.x, y: at.y - Self.height),
			size: Size(width: max(1, text.count) * .mm(1.1) + .mm(0.8), height: Self.height)
		)
	}
}

extension Glyph {

	func placed(_ transform: (Point) -> Point, quarter: Bool) -> Glyph {
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

	var placedPins: [Pin] {
		pins.map { pin in
			modifying(pin) { pin in
				pin.direction = direction(of: pin.direction)
				pin.at = place(pin.at)
			}
		}
	}

	var placedBody: Rect {
		Rect(
			center: place(body.center),
			size: rotation.isQuarter ? body.size.swapped : body.size
		)
	}

	var placedGlyph: [Glyph] {
		glyph.map { shape in shape.placed(place, quarter: rotation.isQuarter) }
	}

	func place(_ local: Point) -> Point {
		(mirrored ? local.mirroredX : local).rotated(rotation) + at
	}

	func direction(of local: Rotation) -> Rotation {
		(mirrored ? local.mirroredX : local).adding(rotation)
	}

	var placedExtent: Rect {
		Rect.union(
			[placedBody]
				+ placedGlyph.map(\.bounds)
				+ placedPins.map { pin in pin.figure.bounds }
		) ?? placedBody
	}
}
