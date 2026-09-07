import CoreGraphics
import Foundation

typealias Nm = Int

extension Nm {
	static var mm: Nm { 1_000_000 }
	static var mil: Nm { 25_400 }
	static var inch: Nm { 25_400_000 }

	static func mm(_ value: Double) -> Nm { Nm(clamping: Int((value * 1_000_000.0).rounded())) }
	static func mil(_ value: Double) -> Nm { Nm(clamping: Int((value * 25_400.0).rounded())) }
	static func inches(_ value: Double) -> Nm { Nm(clamping: Int((value * 25_400_000.0).rounded())) }

	var mm: Double { Double(self) / 1_000_000.0 }
	var mil: Double { Double(self) / 25_400.0 }
	var inches: Double { Double(self) / 25_400_000.0 }
}

struct Point: Hashable, Codable {
	var x: Nm
	var y: Nm

	static var zero: Point { Point(x: 0, y: 0) }

	static prefix func - (point: Point) -> Point { Point(x: -point.x, y: -point.y) }

	static func + (lhs: Point, rhs: Point) -> Point { Point(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
	static func - (lhs: Point, rhs: Point) -> Point { Point(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
	static func * (lhs: Point, rhs: Int) -> Point { Point(x: lhs.x * rhs, y: lhs.y * rhs) }
}

extension Point {

	func snapped(to grid: Nm) -> Point {
		let step = Int(grid)
		guard step > 0 else { return self }
		func round(_ value: Int) -> Int {
			let offset = value < 0 ? -step / 2 : step / 2
			return (value + offset) / step * step
		}
		return Point(x: round(x), y: round(y))
	}

	func distanceSquared(to other: Point) -> Int {
		let dx = x - other.x
		let dy = y - other.y
		return dx * dx + dy * dy
	}

	func isNear(_ other: Point, within radius: Int) -> Bool {
		distanceSquared(to: other) <= radius * radius
	}

	func rotated(_ rotation: Rotation) -> Point {
		switch rotation {
		case .r0: Point(x: x, y: y)
		case .r90: Point(x: -y, y: x)
		case .r180: Point(x: -x, y: -y)
		case .r270: Point(x: y, y: -x)
		}
	}

	var mirroredX: Point { Point(x: -x, y: y) }
}

struct Size: Hashable, Codable {
	var width: Nm
	var height: Nm

	static var zero: Size { Size(width: 0, height: 0) }

	var swapped: Size { Size(width: height, height: width) }
	var isEmpty: Bool { width <= 0 || height <= 0 }
}

struct Rect: Hashable, Codable {
	var origin: Point
	var size: Size

	init(origin: Point, size: Size) {
		self.origin = origin
		self.size = size
	}

	init(center: Point, size: Size) {
		self.init(
			origin: Point(x: center.x - size.width / 2, y: center.y - size.height / 2),
			size: size
		)
	}

	init(from: Point, to: Point) {
		self.init(
			origin: Point(x: Swift.min(from.x, to.x), y: Swift.min(from.y, to.y)),
			size: Size(width: abs(to.x - from.x), height: abs(to.y - from.y))
		)
	}

	var minX: Int { origin.x }
	var minY: Int { origin.y }
	var maxX: Int { origin.x + size.width }
	var maxY: Int { origin.y + size.height }
	var center: Point { Point(x: minX + size.width / 2, y: minY + size.height / 2) }

	func contains(_ point: Point) -> Bool {
		point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
	}

	func intersects(_ other: Rect) -> Bool {
		minX <= other.maxX && maxX >= other.minX && minY <= other.maxY && maxY >= other.minY
	}

	func outset(_ amount: Int) -> Rect {
		Rect(
			origin: Point(x: minX - amount, y: minY - amount),
			size: Size(width: size.width + amount * 2, height: size.height + amount * 2)
		)
	}

	var corners: [Point] {
		[
			Point(x: minX, y: minY),
			Point(x: maxX, y: minY),
			Point(x: maxX, y: maxY),
			Point(x: minX, y: maxY),
		]
	}

	static func union(_ rects: some Sequence<Rect>) -> Rect? {
		var result: Rect?
		for rect in rects {
			guard let current = result else { result = rect; continue }
			let origin = Point(x: Swift.min(current.minX, rect.minX), y: Swift.min(current.minY, rect.minY))
			result = Rect(
				origin: origin,
				size: Size(
					width: Swift.max(current.maxX, rect.maxX) - origin.x,
					height: Swift.max(current.maxY, rect.maxY) - origin.y
				)
			)
		}
		return result
	}
}

enum Rotation: Int, Codable, CaseIterable {
	case r0, r90, r180, r270

	var next: Rotation { Rotation(rawValue: (rawValue + 1) & 0b11) ?? .r0 }
	var previous: Rotation { Rotation(rawValue: (rawValue + 3) & 0b11) ?? .r0 }
	var degrees: Int { rawValue * 90 }
	var isQuarter: Bool { rawValue & 1 == 1 }

	func adding(_ other: Rotation) -> Rotation {
		Rotation(rawValue: (rawValue + other.rawValue) & 0b11) ?? .r0
	}

	var mirroredX: Rotation {
		switch self {
		case .r0: .r180
		case .r180: .r0
		case .r90, .r270: self
		}
	}

	var mirroredY: Rotation {
		switch self {
		case .r90: .r270
		case .r270: .r90
		case .r0, .r180: self
		}
	}
}

enum Stack: Int, Codable, CaseIterable {
	case classic = 2, digital = 4, analog = 6

	var count: Int { rawValue }
	var top: Int { 0 }
	var bottom: Int { rawValue - 1 }
	var copper: Range<Int> { 0 ..< rawValue }
	var internals: Range<Int> { 1 ..< rawValue - 1 }
	var signals: [Int] { [top, bottom] }

	func isInternal(_ layer: Int) -> Bool { internals.contains(layer) }
	func isSignal(_ layer: Int) -> Bool { layer == top || layer == bottom }
	func contains(_ layer: Int) -> Bool { copper.contains(layer) }

	var name: String {
		switch self {
		case .classic: "Classic"
		case .digital: "Digital"
		case .analog: "Analog"
		}
	}

	var roles: [String] {
		switch self {
		case .classic: ["SIG", "SIG"]
		case .digital: ["SIG", "GND", "VCC", "SIG"]
		case .analog: ["SIG", "GND", "VCC", "VEE", "GND", "SIG"]
		}
	}

	var summary: String { roles.joined(separator: " · ") }

	func plane(of layer: Int) -> String? {
		isInternal(layer) ? roles[layer] : nil
	}

	var planeNames: [String] { internals.map { layer in roles[layer] } }

	func signal(matching layer: Int, in old: Stack) -> Int {
		layer == old.top ? top : bottom
	}

	func name(of layer: Int) -> String {
		switch layer {
		case top: "Top"
		case bottom: "Bottom"
		default: "In\(layer)"
		}
	}

	func shortName(of layer: Int) -> String {
		switch layer {
		case top: "T"
		case bottom: "B"
		default: "\(layer)"
		}
	}
}

enum Ref: Hashable, Codable {
	case module(UUID)
	case trace(Int)
	case via(Int)
	case hole(Int)
	case footprint(Int)

	enum Kind: Hashable { case module, trace, via, hole, footprint }

	var kind: Kind {
		switch self {
		case .module: .module
		case .trace: .trace
		case .via: .via
		case .hole: .hole
		case .footprint: .footprint
		}
	}
}
