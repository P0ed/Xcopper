import Foundation

enum Fabrication {

	struct File: Hashable {
		var name: String
		var text: String
	}

	static func write(_ files: [File], to directory: URL) throws {
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		for file in files {
			try file.text.write(
				to: directory.appending(path: file.name),
				atomically: true,
				encoding: .utf8
			)
		}
	}

	static func stem(_ name: String) -> String {
		let cleaned = String(name.map { character in
			character.isLetter || character.isNumber || "-_ ".contains(character)
				? character
				: "_"
		})
		.trimmingWhitespace
		return cleaned.isEmpty ? "Board" : cleaned
	}
}

extension Design {

	func fabrication(named name: String) -> [Fabrication.File] {
		guard moduleErrors.isEmpty else { return [] }
		if !modules.isEmpty { return resolved.fabrication(named: name) }
		let stack = board.stack
		return stack.copper.map { layer in copper(layer, named: name) }
			+ [
				mask(on: stack.top, named: name),
				mask(on: stack.bottom, named: name),
				paste(on: stack.top, named: name),
				paste(on: stack.bottom, named: name),
				profile(named: name),
				drills(plated: true, named: name),
				drills(plated: false, named: name),
			]
	}
}

private extension Design {

	var height: Int { board.size.height }

	func copper(_ layer: Int, named name: String) -> Fabrication.File {
		var gerber = Gerber(height: height, function: board.stack.function(of: layer))

		if let plane = plane(layer) {
			gerber.region(
				board.bounds.outset(-Int(board.rules.clearance)),
				net: net(plane)?.name
			)
			gerber.polarity(.clear)
			for figure in board.clearances(on: layer, net: plane) {
				gerber.fill(figure)
			}
			gerber.polarity(.dark)
		}
		for (figure, id) in board.figures(on: layer) {
			gerber.fill(figure, net: net(id)?.name)
		}
		return file(gerber, name: name, suffix: board.stack.suffix(of: layer))
	}

	func mask(on layer: Int, named name: String) -> Fabrication.File {
		var gerber = Gerber(
			height: height,
			function: "Soldermask,\(board.stack.sideName(of: layer))",
			negative: true
		)
		for pad in board.pads(on: layer) {
			gerber.fill(pad.figure.outset(Int(Gerber.maskExpansion)))
		}
		return file(gerber, name: name, suffix: "\(board.stack.side(of: layer))_Mask")
	}

	func paste(on layer: Int, named name: String) -> Fabrication.File {
		var gerber = Gerber(
			height: height,
			function: "SolderPaste,\(board.stack.sideName(of: layer))"
		)
		for pad in board.pads(on: layer) where !pad.isThrough {
			gerber.fill(pad.figure)
		}
		return file(gerber, name: name, suffix: "\(board.stack.side(of: layer))_Paste")
	}

	func profile(named name: String) -> Fabrication.File {
		var gerber = Gerber(height: height, function: "Profile,NP")
		gerber.stroke(board.bounds, width: Gerber.outlineWidth)
		return file(gerber, name: name, suffix: "Edge_Cuts")
	}

	func drills(plated: Bool, named name: String) -> Fabrication.File {
		var program = Excellon(height: height, layers: board.stack.count, plated: plated)

		if plated {
			for via in board.vias {
				program.drill(via.drill, at: via.at)
			}
			for footprint in board.footprints {
				for pad in footprint.placedPads where pad.isThrough {
					program.drill(pad.drill, at: pad.at)
				}
			}
		} else {
			for hole in board.holes {
				program.drill(hole.diameter, at: hole.at)
			}
		}
		return Fabrication.File(
			name: "\(name)-\(plated ? "PTH" : "NPTH").drl",
			text: program.text
		)
	}

	func file(_ gerber: Gerber, name: String, suffix: String) -> Fabrication.File {
		Fabrication.File(name: "\(name)-\(suffix).gbr", text: gerber.text)
	}
}

extension Stack {

	func suffix(of layer: Int) -> String {
		switch layer {
		case top: "F_Cu"
		case bottom: "B_Cu"
		default: "In\(layer)_Cu"
		}
	}

	func function(of layer: Int) -> String {
		let side = switch layer {
		case top: "Top"
		case bottom: "Bot"
		default: "Inr"
		}
		return "Copper,L\(layer + 1),\(side)"
	}

	func side(of layer: Int) -> String { layer == top ? "F" : "B" }

	func sideName(of layer: Int) -> String { layer == top ? "Top" : "Bot" }
}
