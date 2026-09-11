import SwiftUI

@MainActor
final class LayoutRenderCache {
	private struct Move: Equatable {
		var delta: Point
		var selection: Set<Ref>
		var grid: µm
	}

	private var source: Design?
	private var move: Move?
	private var projection: ModuleProjection?
	private var movedSelection: Set<Ref>?
	private var drawing: LayoutDrawing?
	private var selection: Set<Ref>?
	private var picked = LayoutPickedDrawing()

	func value(for design: Design, state: LayoutState) -> (LayoutDrawing, LayoutPickedDrawing) {
		let move = state.moveSession.flatMap { session in
			session.didMove ? Move(delta: session.delta, selection: state.selection, grid: state.routingGrid) : nil
		}
		if source != design || self.move != move || drawing == nil {
			var moved = design
			movedSelection = move.flatMap { moved.moveLayout($0.selection, by: $0.delta, grid: $0.grid) }
			let projection = moved.moduleProjection()
			self.projection = projection
			drawing = LayoutDrawing(design: projection.design, modules: moved.modules)
			source = design
			self.move = move
			selection = nil
		}
		if selection != state.selection {
			let expanded = projection!.expanded(movedSelection ?? state.selection)
			picked = LayoutPickedDrawing(board: drawing!.board, selection: expanded)
			selection = state.selection
		}
		return (drawing!, picked)
	}
}

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

	init() {}

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
	for figure in figures { path.addPath(figure.path(1, origin: .zero)) }
	return path
}
