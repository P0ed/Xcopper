import SwiftUI

enum Palette {
	static let substrate = Color(red: 0.09, green: 0.11, blue: 0.10)
	static let outline = Color(red: 0.85, green: 0.87, blue: 0.60)
	static let grid = Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.16)
	static let drill = Color(red: 0.04, green: 0.05, blue: 0.05)
	static let silk = Color(red: 0.92, green: 0.92, blue: 0.90)
	static let highlight = Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.9)
	static let preview = Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.55)

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
}
