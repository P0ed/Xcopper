import Foundation

struct Excellon {
	private let height: Int
	private let layers: Int
	private let plated: Bool
	private var tools: [µm: [Point]] = [:]

	init(height: Int, layers: Int, plated: Bool) {
		self.height = height
		self.layers = layers
		self.plated = plated
	}

	mutating func drill(_ diameter: µm, at point: Point) {
		guard diameter > 0 else { return }
		tools[diameter, default: []].append(point)
	}

	var text: String {
		let diameters = tools.keys.sorted()
		var out = [
			"M48",
			";DRILL file {Xcopper}",
			";FORMAT={-:-/ absolute / metric / decimal}",
			"; #@! TF.FileFunction,\(function)",
			"; #@! TF.FilePolarity,Positive",
			";TYPE=\(plated ? "PLATED" : "NON_PLATED")",
			"FMAT,2",
			"METRIC",
		]
		out += diameters.enumerated().map { index, diameter in
			"T\(index + 1)C\(String.mm(diameter, decimals: 3))"
		}
		out += ["%", "G90", "G05"]

		for (index, diameter) in diameters.enumerated() {
			out.append("T\(index + 1)")
			out += (tools[diameter] ?? []).map { point in
				"X\(String.mm(point.x, decimals: 4))Y\(String.mm(height - point.y, decimals: 4))"
			}
		}
		out += ["T0", "M30"]
		return out.joined(separator: "\n") + "\n"
	}

	private var function: String {
		plated ? "Plated,1,\(layers),PTH" : "NonPlated,1,\(layers),NPTH"
	}
}
