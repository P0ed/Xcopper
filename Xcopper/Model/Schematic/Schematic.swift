import Foundation

struct Pin: Hashable, Codable {
	var at: Point
	var direction: Rotation
	var length: µm
	var name: String
	var number: String
	var netLabel: String?
}

struct IODesignator: Hashable, Codable {
	var number: Int
	var name: String

	init(number: Int, name: String) {
		self.number = number
		self.name = name
	}

	init?(_ label: String) {
		let text = label.trimmingWhitespace
		guard text.hasPrefix("#") else { return nil }
		let suffix = text.dropFirst()
		let digits = suffix.prefix { $0.isASCII && $0.isNumber }
		let rest = suffix.dropFirst(digits.count)
		guard let number = Int(digits), number > 0, rest.first?.isWhitespace == true else { return nil }
		let name = String(rest).trimmingWhitespace
		guard !name.isEmpty else { return nil }
		self.init(number: number, name: name)
	}

	static func order(_ lhs: Self, _ rhs: Self) -> Bool {
		(lhs.number, lhs.name) < (rhs.number, rhs.name)
	}
}

enum PinText {
	static let nameHeight = 1_270
	static let numberHeight = 1_016
	static let inset = 762
	static let gap = 254
	static let advance = 62

	static func width(_ text: String, height: Int = nameHeight) -> Int {
		(text.count * height * advance + 50) / 100
	}
}

enum Glyph: Hashable, Codable {
	case path([Point], closed: Bool, filled: Bool)
	case rect(Rect)
	case circle(Point, µm)
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
	var valueParameter: Bool?
}

struct Wire: Hashable, Codable {
	var start: Point
	var end: Point
}

struct Schematic: Equatable, Codable {
	var size: Size
	var symbols: [Symbol]
	var wires: [Wire]
}

extension Schematic {

	enum Ref: Hashable, Codable {
		case module(UUID)
		case symbol(Int)
		case wire(Int)

		enum Kind: Hashable { case module, symbol, wire }

		var kind: Kind {
			switch self {
			case .module: .module
			case .symbol: .symbol
			case .wire: .wire
			}
		}

		var index: Int {
			switch self {
			case .module: Int.max
			case let .symbol(index), let .wire(index): index
			}
		}

		static func order(_ lhs: Ref, _ rhs: Ref) -> Bool { lhs.index < rhs.index }
	}

	init(size: Size = .init(width: 297 * .mm, height: 210 * .mm)) {
		self.size = size
		symbols = []
		wires = []
	}

	var bounds: Rect { Rect(origin: .zero, size: size) }
}

extension Pin {

	var root: Point { at + Point(x: -Int(length), y: 0).rotated(direction) }

	var figure: Figure { .segment(at, root, 200) }

	var isNamed: Bool { !name.isEmpty && name != number }

	var ioDesignator: IODesignator? { netLabel.flatMap(IODesignator.init) }

	var netName: String? {
		guard let text = netLabel?.trimmingWhitespace, !text.isEmpty else { return nil }
		return text.hasPrefix("#") ? ioDesignator?.name : text
	}

	var hasInvalidIO: Bool {
		netLabel?.trimmingWhitespace.hasPrefix("#") == true && ioDesignator == nil
	}
}

extension Wire {
	var figure: Figure { .segment(start, end, 200) }
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
