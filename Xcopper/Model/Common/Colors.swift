import AppKit
import SwiftUI

enum Palette {
	static let substrate = Color(red: 0.09, green: 0.11, blue: 0.10)
	static let outline = Color(red: 0.85, green: 0.87, blue: 0.60)
	static let grid = Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.16)
	static let gridMajor = Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.32)
	static let drill = Color(red: 0.04, green: 0.05, blue: 0.05)
	static let silk = Color(red: 0.92, green: 0.92, blue: 0.90)
	static let highlight = Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.9)
	static let preview = Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.55)
	static let halo = Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.35)
	static let violation = Color(red: 1.0, green: 0.36, blue: 0.30)

	static let sheet = Color(red: 0.10, green: 0.10, blue: 0.13)
	static let symbol = Color(red: 0.88, green: 0.88, blue: 0.86)
	static let pin = Color(red: 0.85, green: 0.74, blue: 0.35)
	static let wire = Color(red: 0.55, green: 0.80, blue: 0.60)
	static let junction = Color(red: 0.95, green: 0.95, blue: 0.90)

	static let copper: [Color] = [
		Color(red: 0.78, green: 0.16, blue: 0.16),
		Color(red: 0.30, green: 0.66, blue: 0.30),
		Color(red: 0.85, green: 0.72, blue: 0.20),
		Color(red: 0.78, green: 0.35, blue: 0.72),
		Color(red: 0.25, green: 0.72, blue: 0.72),
		Color(red: 0.25, green: 0.42, blue: 0.86),
	]

	static func color(of layer: Int, in stack: Stack) -> Color {
		switch layer {
		case stack.top: copper[0]
		case stack.bottom: copper[5]
		default: copper[(layer - 1) % 4 + 1]
		}
	}

	static func color(of net: Net.ID) -> Color {
		Color(hue: Double(net &* 47 % 360) / 360.0, saturation: 0.55, brightness: 0.95)
	}

	static func lit(_ color: Color) -> Color {
		guard let base = NSColor(color).usingColorSpace(.sRGB) else { return highlight }

		func up(_ value: CGFloat) -> Double { Double(value + (1.0 - value) * 0.55) }

		return Color(
			red: up(base.redComponent),
			green: up(base.greenComponent),
			blue: up(base.blueComponent),
			opacity: Double(base.alphaComponent)
		)
	}

	static func color(named name: String) -> Color {
		var hash = 5381
		for byte in name.utf8 { hash = (hash &* 33) &+ Int(byte) }
		return Color(hue: Double(abs(hash) % 360) / 360.0, saturation: 0.55, brightness: 0.95)
	}
}

enum Mask: String, CaseIterable, Identifiable {
	case green, black, clear

	var id: String { rawValue }
	var name: String { rawValue.capitalized }

	var rgb: RGBA {
		switch self {
		case .green: RGBA(r: 0.05, g: 0.33, b: 0.17)
		case .black: RGBA(r: 0.10, g: 0.10, b: 0.11)
		case .clear: RGBA(r: 0.56, g: 0.47, b: 0.33)
		}
	}

	var covers: Bool { self != .clear }
}

enum Plating: String, CaseIterable, Identifiable {
	case gold

	var id: String { rawValue }
	var name: String { "ENIG" }

	var rgb: RGBA {
		switch self {
		case .gold: RGBA(r: 0.82, g: 0.68, b: 0.33)
		}
	}
}

extension Palette {
	static let bareCopper = RGBA(r: 0.72, g: 0.45, b: 0.20)
	static let laminate = RGBA(r: 0.76, g: 0.68, b: 0.42)
	static let solder = RGBA(r: 0.70, g: 0.71, b: 0.73)
	static let moulding = RGBA(r: 0.13, g: 0.13, b: 0.14)
	static let chip = RGBA(r: 0.19, g: 0.17, b: 0.16)
	static let ceramic = RGBA(r: 0.85, g: 0.60, b: 0.20)
	static let nylon = RGBA(r: 0.85, g: 0.84, b: 0.79)
	static let trimmer = RGBA(r: 0.11, g: 0.24, b: 0.58)
	static let lens = RGBA(r: 0.92, g: 0.92, b: 0.94, a: 0.82)
	static let metal = RGBA(r: 0.62, g: 0.63, b: 0.66)
	static let backdrop = Color(red: 0.07, green: 0.08, blue: 0.09)
}
