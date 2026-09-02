import Foundation

/// An RS-274X file under construction.
///
/// Board nanometers are exactly the unit of the 4.6 millimeter coordinate
/// format, so a coordinate goes out as its own integer and nothing rounds on
/// the way. Y is flipped: Gerber counts up from the bottom left corner, the
/// board counts down from the top left one.
struct Gerber {

	/// The shape a flash puts down, or that a draw sweeps along its line
	enum Aperture: Hashable {
		case circle(Nm)
		case rect(Size)
	}

	enum Polarity: String {
		case dark = "D"
		case clear = "C"
	}

	private let height: Int
	private let function: String
	private let polarity: String

	private var apertures: [Aperture] = []
	private var codes: [Aperture: Int] = [:]
	private var selected: Int?

	/// Net attribute standing on the objects written next, unset until the
	/// first one is written
	private var attached: String??
	private var lines: [String] = []

	init(height: Int, function: String, negative: Bool = false) {
		self.height = height
		self.function = function
		polarity = negative ? "Negative" : "Positive"
	}
}

extension Gerber {

	/// Widths and expansions the fabrication set is drawn with
	static var outlineWidth: Nm { .mm(0.1) }
	static var maskExpansion: Nm { .mm(0.05) }
}

extension Gerber {

	/// The copper, mask opening or paste opening one figure stands for
	mutating func fill(_ figure: Figure, net: String? = nil) {
		attach(net)
		switch figure {
		case let .rect(rect):
			flash(.rect(rect.size), at: rect.center)
		case let .round(center, diameter):
			flash(.circle(diameter), at: center)
		case let .segment(start, end, width):
			draw([start, end], width: width)
		}
	}

	/// A closed outline, for the one file that says where to cut
	mutating func stroke(_ rect: Rect, width: Nm) {
		draw(rect.corners + [rect.corners[0]], width: width)
	}

	/// A filled polygon, for the plane pour no aperture is big enough to flash
	mutating func region(_ rect: Rect, net: String? = nil) {
		guard !rect.size.isEmpty else { return }
		attach(net)
		lines.append("G36*")
		lines.append("\(coordinate(rect.corners[0]))D02*")
		for corner in rect.corners.dropFirst() + [rect.corners[0]] {
			lines.append("\(coordinate(corner))D01*")
		}
		lines.append("G37*")
	}

	/// Everything written from here on adds copper, or clears it back out of
	/// what a `.dark` pass laid down
	mutating func polarity(_ polarity: Polarity) {
		lines.append("%LP\(polarity.rawValue)*%")
	}

	/// The finished file
	var text: String {
		var out = [
			"G04 Xcopper*",
			"%TF.GenerationSoftware,Xcopper*%",
			"%TF.FileFunction,\(function)*%",
			"%TF.FilePolarity,\(polarity)*%",
			"%TF.Part,Single*%",
			"%FSLAX46Y46*%",
			"%MOMM*%",
		]
		out += apertures.enumerated().map { index, aperture in
			"%ADD\(Gerber.first + index)\(aperture.definition)*%"
		}
		out += ["G01*", "%LPD*%"]
		out += lines
		out.append("M02*")
		return out.joined(separator: "\n") + "\n"
	}
}

private extension Gerber {

	/// Lowest D code the standard leaves for apertures
	static var first: Int { 10 }

	mutating func flash(_ aperture: Aperture, at point: Pt) {
		guard aperture.isDrawable else { return }
		select(aperture)
		lines.append("\(coordinate(point))D03*")
	}

	mutating func draw(_ points: [Pt], width: Nm) {
		guard points.count > 1, width > 0 else { return }
		select(.circle(width))
		lines.append("\(coordinate(points[0]))D02*")
		for point in points.dropFirst() {
			lines.append("\(coordinate(point))D01*")
		}
	}

	mutating func select(_ aperture: Aperture) {
		let code = code(for: aperture)
		guard selected != code else { return }
		selected = code
		lines.append("D\(code)*")
	}

	mutating func code(for aperture: Aperture) -> Int {
		if let code = codes[aperture] { return code }
		let code = Gerber.first + apertures.count
		apertures.append(aperture)
		codes[aperture] = code
		return code
	}

	mutating func attach(_ net: String?) {
		guard attached != .some(net) else { return }
		if attached != nil || net != nil {
			lines.append(net.map { "%TO.N,\(Gerber.escaped($0))*%" } ?? "%TD*%")
		}
		attached = .some(net)
	}

	func coordinate(_ point: Pt) -> String {
		"X\(point.x)Y\(height - point.y)"
	}

	/// An attribute value may not carry the characters that delimit it
	static func escaped(_ name: String) -> String {
		String(name.map { character in "%*,\\".contains(character) ? "_" : character })
	}
}

extension Gerber.Aperture {

	var definition: String {
		switch self {
		case let .circle(diameter):
			"C,\(millimeters(Int(diameter)))"
		case let .rect(size):
			"R,\(millimeters(size.width))X\(millimeters(size.height))"
		}
	}

	var isDrawable: Bool {
		switch self {
		case let .circle(diameter): diameter > 0
		case let .rect(size): !size.isEmpty
		}
	}
}

func millimeters(_ value: Int, decimals: Int = 6) -> String {
	String(format: "%.\(decimals)f", Double(value) / 1_000_000.0)
}
