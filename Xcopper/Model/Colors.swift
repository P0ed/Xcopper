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

	/// Copper colour for `layer`, with bottom always reading blue
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

	/// Colour for a net the schematic knows only by name. Seeded by hand because
	/// `hashValue` is salted per process and would change between launches.
	static func color(named name: String) -> Color {
		var hash = 5381
		for byte in name.utf8 { hash = (hash &* 33) &+ Int(byte) }
		return Color(hue: Double(abs(hash) % 360) / 360.0, saturation: 0.55, brightness: 0.95)
	}
}

/// Solder mask colour, the one thing about a bare board people pick by eye
enum Mask: String, CaseIterable, Identifiable {
	case green, red, blue, black, white, purple

	var id: String { rawValue }
	var name: String { rawValue.capitalized }

	var rgb: Rgb {
		switch self {
		case .green: Rgb(r: 0.05, g: 0.33, b: 0.17)
		case .red: Rgb(r: 0.46, g: 0.08, b: 0.08)
		case .blue: Rgb(r: 0.06, g: 0.17, b: 0.46)
		case .black: Rgb(r: 0.10, g: 0.10, b: 0.11)
		case .white: Rgb(r: 0.86, g: 0.86, b: 0.84)
		case .purple: Rgb(r: 0.24, g: 0.09, b: 0.37)
		}
	}
}

/// What the fab leaves on the pads the mask does not cover
enum Plating: String, CaseIterable, Identifiable {
	case gold, tin

	var id: String { rawValue }
	var name: String { self == .gold ? "ENIG" : "HASL" }

	var rgb: Rgb {
		switch self {
		case .gold: Rgb(r: 0.85, g: 0.68, b: 0.31)
		case .tin: Rgb(r: 0.76, g: 0.78, b: 0.80)
		}
	}
}

/// Materials for the 3D preview. Kept as components rather than `Color` so a
/// face can be shaded by scaling it before it reaches the canvas.
extension Palette {
	/// Bare copper, seen through the mask rather than on its own
	static let bareCopper = Rgb(r: 0.72, g: 0.45, b: 0.20)
	/// Cut edge of the laminate, and the wall of an unplated hole
	static let laminate = Rgb(r: 0.76, g: 0.68, b: 0.42)
	/// Solder, and the leads it covers
	static let solder = Rgb(r: 0.70, g: 0.71, b: 0.73)
	/// Moulded epoxy, the body of most packages
	static let moulding = Rgb(r: 0.13, g: 0.13, b: 0.14)
	/// Ceramic and film chips
	static let chip = Rgb(r: 0.19, g: 0.17, b: 0.16)
	/// Natural nylon, what connector shrouds are moulded from
	static let nylon = Rgb(r: 0.85, g: 0.84, b: 0.79)
	static let trimmer = Rgb(r: 0.11, g: 0.24, b: 0.58)
	/// A clear lens, which the board shows through
	static let lens = Rgb(r: 0.92, g: 0.92, b: 0.94, a: 0.82)
	static let metal = Rgb(r: 0.62, g: 0.63, b: 0.66)

	/// Behind the board, dark enough that a black mask still reads against it
	static let backdrop = Color(red: 0.07, green: 0.08, blue: 0.09)
}
