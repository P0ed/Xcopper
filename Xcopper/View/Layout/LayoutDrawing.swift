import SwiftUI

struct LayoutDrawing {
	var board: Board
	var modules: [ModuleInstance]
	var copper: [Int: Path] = [:]
	var clearances: [Int: [Path]] = [:]
	var drills: Path
	var ratsnest: [Net.ID: Path] = [:]
	var violations: [Point]

	init(design: Design, modules: [ModuleInstance]) {
		board = design.board
		self.modules = modules
		for layer in board.stack.copper {
			copper[layer] = layoutPath(board.figures(on: layer).map(\.0))
			if let net = design.plane(layer) {
				clearances[layer] = board.clearances(on: layer, net: net).map { $0.path(1, origin: .zero) }
			}
		}
		drills = layoutPath(board.drills)
		for rat in board.ratsnest(planes: design.planes) {
			ratsnest[rat.net, default: Path()].move(to: rat.from.cg(1, origin: .zero))
			ratsnest[rat.net, default: Path()].addLine(to: rat.to.cg(1, origin: .zero))
		}
		violations = design.faults().map(\.at)
	}
}

struct LayoutPickedDrawing {
	var selection: Set<Ref> = []
	var copper: [Int: Path] = [:]
	var drills = Path()

	init(board: Board, selection: Set<Ref>) {
		self.selection = selection
		for layer in board.stack.copper {
			copper[layer] = layoutPath(board.figures(on: layer, of: selection))
		}
		for case let .hole(index) in selection where board.holes.indices.contains(index) {
			let hole = board.holes[index]
			drills.addPath(Figure.round(hole.at, hole.diameter).path(1, origin: .zero))
		}
	}
}

private func layoutPath(_ figures: [Figure]) -> Path {
	var path = Path()
	for figure in figures { path.addPath(figure.path(1, origin: .zero).normalized(eoFill: false)) }
	return path
}
