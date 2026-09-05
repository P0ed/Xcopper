import Foundation

struct Gerber {

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

	private var attached: String??
	private var lines: [String] = []

	init(height: Int, function: String, negative: Bool = false) {
		self.height = height
		self.function = function
		polarity = negative ? "Negative" : "Positive"
	}
}

extension Gerber {

	static var outlineWidth: Nm { .mm(0.1) }
	static var maskExpansion: Nm { .mm(0.05) }
}

extension Gerber {

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

	mutating func stroke(_ rect: Rect, width: Nm) {
		draw(rect.corners + [rect.corners[0]], width: width)
	}

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

	mutating func polarity(_ polarity: Polarity) {
		lines.append("%LP\(polarity.rawValue)*%")
	}

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
