import CoreGraphics
import simd
import SwiftUI

struct V3: Hashable {
	var x: Double
	var y: Double
	var z: Double
}

extension V3 {

	static var zero: V3 { V3(x: 0.0, y: 0.0, z: 0.0) }

	static func + (lhs: V3, rhs: V3) -> V3 {
		V3(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
	}

	static func - (lhs: V3, rhs: V3) -> V3 {
		V3(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
	}

	static func * (lhs: V3, rhs: Double) -> V3 {
		V3(x: lhs.x * rhs, y: lhs.y * rhs, z: lhs.z * rhs)
	}

	static prefix func - (value: V3) -> V3 { value * -1.0 }

	func dot(_ other: V3) -> Double { x * other.x + y * other.y + z * other.z }

	func cross(_ other: V3) -> V3 {
		V3(
			x: y * other.z - z * other.y,
			y: z * other.x - x * other.z,
			z: x * other.y - y * other.x
		)
	}

	var length: Double { dot(self).squareRoot() }

	var normalized: V3 {
		let length = length
		return length > 0.0 ? self * (1.0 / length) : self
	}

	static func box(
		x: ClosedRange<Double>,
		y: ClosedRange<Double>,
		z: ClosedRange<Double>
	) -> [V3] {
		[x.lowerBound, x.upperBound].flatMap { x in
			[y.lowerBound, y.upperBound].flatMap { y in
				[z.lowerBound, z.upperBound].map { z in V3(x: x, y: y, z: z) }
			}
		}
	}
}

extension Pt {

	func v3(_ z: Double) -> V3 { V3(x: Double(x).mm, y: Double(y).mm, z: z) }
}

extension [V3] {

	var normal: V3 {
		var normal = V3.zero
		guard var previous = last else { return normal }
		for point in self {
			normal.x += (previous.y - point.y) * (previous.z + point.z)
			normal.y += (previous.z - point.z) * (previous.x + point.x)
			normal.z += (previous.x - point.x) * (previous.y + point.y)
			previous = point
		}
		return normal.normalized
	}
}

struct Camera: Equatable {
	var target: V3 = .zero
	var azimuth: Double = -.pi / 7.0
	var elevation: Double = .pi / 5.0
	var distance: Double = 120.0
	var fov: Double = .pi / 7.0
}

extension Camera {

	var forward: V3 {
		V3(
			x: cos(elevation) * sin(azimuth),
			y: -cos(elevation) * cos(azimuth),
			z: -sin(elevation)
		)
	}

	var right: V3 { V3(x: cos(azimuth), y: sin(azimuth), z: 0.0) }
	var up: V3 { forward.cross(right) }
	var eye: V3 { target - forward * distance }
	var overTop: Bool { elevation >= 0.0 }

	mutating func orbit(by delta: CGSize) {
		azimuth = (azimuth - Double(delta.width) * 0.01)
			.truncatingRemainder(dividingBy: .pi * 2.0)
		elevation = min(max(elevation + Double(delta.height) * 0.01, -.pi / 2.0), .pi / 2.0)
	}

	mutating func pan(by delta: CGSize, over pixels: Double) {
		let span = 2.0 * distance * tan(fov / 2.0) / max(pixels, 1.0)
		target = target
			- right * (Double(delta.width) * span)
			+ up * (Double(delta.height) * span)
	}

	mutating func zoom(to distance: Double, reach: Double) {
		self.distance = min(max(distance, reach / 24.0), reach * 6.0)
	}

	mutating func zoom(by factor: Double, reach: Double) {
		zoom(to: distance / factor, reach: reach)
	}

	mutating func aim(at stand: Standpoint) {
		azimuth = stand.azimuth
		elevation = stand.elevation
	}
}

enum Standpoint: Hashable, CaseIterable, Identifiable {
	case top, bottom, front, back, left, right, angled

	var id: Self { self }

	var name: String {
		switch self {
		case .top: "Top"
		case .bottom: "Bottom"
		case .front: "Front"
		case .back: "Back"
		case .left: "Left"
		case .right: "Right"
		case .angled: "Angled"
		}
	}

	var systemImage: String {
		switch self {
		case .top: "t.square"
		case .bottom: "b.square"
		case .front: "f.square"
		case .back: "k.square"
		case .left: "l.square"
		case .right: "r.square"
		case .angled: "a.square"
		}
	}

	var azimuth: Double {
		switch self {
		case .top, .bottom, .front: 0.0
		case .back: .pi
		case .left: .pi / 2.0
		case .right: -.pi / 2.0
		case .angled: -.pi / 7.0
		}
	}

	var elevation: Double {
		switch self {
		case .top: .pi / 2.0
		case .bottom: -.pi / 2.0
		case .front, .back, .left, .right: 0.0
		case .angled: .pi / 5.0
		}
	}
}

extension V3 {
	var turned: SIMD3<Float> { SIMD3(Float(x), Float(z), Float(y)) }
	var placed: SIMD3<Float> { turned * Float(V3.metre) }
	static let metre = 0.001
}

extension Camera {

	static let near = 0.25
	static let far = 10_000.0
	var pose: simd_float4x4 {
		simd_float4x4(columns: (
			SIMD4(right.turned, 0.0),
			SIMD4(up.turned, 0.0),
			SIMD4((-forward).turned, 0.0),
			SIMD4(eye.placed, 1.0)
		))
	}
}

struct RGBA: Hashable {
	var r: Double
	var g: Double
	var b: Double
	var a: Double = 1.0
}

extension RGBA {

	var color: Color { Color(red: r, green: g, blue: b, opacity: a) }

	func scaled(_ factor: Double) -> RGBA {
		RGBA(r: min(r * factor, 1.0), g: min(g * factor, 1.0), b: min(b * factor, 1.0), a: a)
	}

	func mixed(with other: RGBA, _ amount: Double) -> RGBA {
		RGBA(
			r: r + (other.r - r) * amount,
			g: g + (other.g - g) * amount,
			b: b + (other.b - b) * amount,
			a: a + (other.a - a) * amount
		)
	}

	func opacity(_ value: Double) -> RGBA { modifying(self) { $0.a = value } }
}
