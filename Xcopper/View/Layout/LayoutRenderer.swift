import SwiftUI

@MainActor
struct LayoutRenderer {
	var design: Design
	var selection: Set<Ref>
	var modules: [ModuleInstance]
	var unresolved: Set<ModuleInstance.ID>
	var ratsnest: [Rat]
	var violations: [Point]

	init(design: Design, state: LayoutState) {
		var moved = design
		var selection = state.selection
		if let placement = state.modulePlacement {
			let id = moved.placeModule(placement, at: state.viewport.cursor.snapped(to: state.placementGrid), layout: true)
			selection = [.module(id)]
		}
		if let session = state.moveSession, session.didMove,
			let next = moved.moveLayout(selection, by: session.delta, grid: state.routingGrid) { selection = next }
		let projection = moved.moduleProjection()
		self.design = projection.design
		self.selection = projection.expanded(selection)
		modules = moved.modules
		unresolved = Set(moved.modules.filter { moved.moduleStatus($0.id) != nil }.map(\.id))
		ratsnest = projection.design.board.ratsnest(planes: projection.design.planes)
		violations = projection.design.faults().map(\.at)
	}

	var board: Board { design.board }

	func copper(_ state: LayoutState) -> Model {
		var drawing = LayoutDrawing()
		let drills = board.drills
		drawing.fill(.rect(board.bounds), color: Palette.substrate, level: 0, cutouts: drills)
		for (index, layer) in layers(state).enumerated() {
			let level = 10 + index * 4
			if let net = design.plane(layer) {
				let bounds = board.bounds.outset(-Int(board.rules.clearance))
				if bounds.size.width > 0, bounds.size.height > 0 {
					drawing.fill(
						.rect(bounds), color: Palette.innerCopper, level: level,
						cutouts: board.clearances(on: layer, net: net) + drills
					)
				}
			}
			let color = state.copperColor(layer)
			for (figure, _) in board.figures(on: layer) {
				drawing.fill(figure, color: color, level: level + 1, cutouts: drills)
			}
		}
		for drill in drills { drawing.fill(drill, color: Palette.background, level: 40) }
		return drawing.model
	}

	func guides(_ state: LayoutState) -> Model {
		var drawing = LayoutDrawing()
		let scale = state.viewport.magnification
		let drills = board.drills
		func pixels(_ value: CGFloat) -> µm { max(1, Int((value * CGFloat(µm.mm) / scale).rounded())) }

		for layer in layers(state) {
			let color = Palette.lit(state.copperColor(layer))
			for figure in board.figures(on: layer, of: selection) {
				drawing.fill(figure.outset(pixels(2)), color: Palette.halo, level: 50, cutouts: drills)
				drawing.fill(figure, color: color, level: 51, cutouts: drills)
			}
		}
		for case let .hole(index) in selection where board.holes.indices.contains(index) {
			let hole = board.holes[index]
			drawing.outline(.round(hole.at, hole.diameter), width: pixels(1.5), color: Palette.highlight, level: 52)
		}
		if state.silkscreen {
			for (index, footprint) in board.footprints.enumerated() {
				let color = selection.contains(.footprint(index)) ? Palette.highlight : Palette.silk.opacity(0.5)
				if footprint.appearance.stands || footprint.package == .nkkMNPC || footprint.package == .bourns51 || footprint.package == .led5mm {
					drawing.stroke(footprint.placedBody.corners, closed: true, width: pixels(1), color: color, level: 60)
				}
				let marker = footprint.place(footprint.pads.first?.at ?? .zero)
				drawing.outline(.round(marker, max(pixels(2), 240)), width: pixels(1), color: color, level: 60)
			}
			for module in modules {
				drawing.stroke(
					module.bounds.corners, closed: true, width: pixels(1),
					color: unresolved.contains(module.id) ? .red : Palette.silk.opacity(0.5), level: 60
				)
			}
		}
		for rat in ratsnest {
			drawing.stroke([rat.from, rat.to], width: pixels(0.75), color: Palette.color(of: rat.net).opacity(0.8), level: 70, dash: pixels(3))
		}
		drawing.stroke(board.bounds.corners, closed: true, width: pixels(1.5), color: Palette.outline, level: 80)
		for at in violations {
			drawing.outline(.round(at, pixels(12)), width: pixels(1.5), color: Palette.violation, level: 90)
			drawing.fill(.round(at, pixels(2.5)), color: Palette.violation, level: 90)
		}
		return drawing.model
	}

	func grid(_ state: LayoutState) -> Model {
		var drawing = LayoutDrawing()
		let scale = state.viewport.magnification
		let step = Int(state.grid)
		let spacing = CGFloat(Double.mm(step)) * scale
		guard step > 0, spacing * 10 >= 3 else { return drawing.model }

		let bounds = board.bounds
		let pitch = step
		let size = max(1, Int(1.0 * CGFloat(µm.mm) / scale))

		for x in stride(from: ((bounds.minX + pitch - 1) / pitch) * pitch, through: bounds.maxX, by: pitch) {
			drawing.fill(
				.rect(Rect(origin: Point(x: x, y: 0), size: Size(width: size, height: bounds.size.height))),
				color: Palette.grid, level: 2
			)
		}
		for y in stride(from: ((bounds.minY + pitch - 1) / pitch) * pitch, through: bounds.maxY, by: pitch) {
			drawing.fill(
				.rect(Rect(origin: Point(x: 0, y: y), size: Size(width: bounds.size.width, height: size))),
				color: Palette.grid, level: 2
			)
		}
		return drawing.model
	}

	func sessions(_ state: LayoutState) -> Model {
		var drawing = LayoutDrawing()
		func pixels(_ value: CGFloat) -> µm { max(1, Int((value * CGFloat(µm.mm) / state.viewport.magnification).rounded())) }
		if let placement = state.modulePlacement,
			let module = modules.first(where: { $0.id == placement.instance.id }) {
			drawing.stroke(module.bounds.corners, closed: true, width: pixels(1.5), color: Palette.preview, level: 100)
		}
		if let session = state.traceSession, session.didDraw {
			let figure = Figure.segment(session.start, session.end, state.traceWidth ?? board.rules.traceWidth)
			drawing.fill(figure, color: Palette.activeCopper, level: 100)
			drawing.outline(figure, width: pixels(0.75), color: Palette.preview, level: 101)
		}
		if let session = state.selectSession, session.didDrag {
			drawing.stroke(session.rect.corners, closed: true, width: pixels(2), color: .black, level: 110)
			drawing.stroke(session.rect.corners, closed: true, width: pixels(1), color: Palette.highlight, level: 111, dash: pixels(4))
		}
		if state.tool != .select || state.modulePlacement != nil {
			let at = state.modulePlacement == nil ? state.viewport.cursor : state.viewport.cursor.snapped(to: state.placementGrid)
			let arm = pixels(8)
			drawing.stroke([at - Point(x: arm, y: 0), at + Point(x: arm, y: 0)], width: pixels(1), color: Palette.preview, level: 120)
			drawing.stroke([at - Point(x: 0, y: arm), at + Point(x: 0, y: arm)], width: pixels(1), color: Palette.preview, level: 120)
		}
		return drawing.model
	}

	private func layers(_ state: LayoutState) -> [Int] {
		(board.stack.copper.filter { $0 != state.layer } + [state.layer]).filter { state[visible: $0] }
	}
}

private extension LayoutState {

	func copperColor(_ layer: Int) -> Color {
		if layer == self.layer {
			Palette.activeCopper
		} else if layer == stack.top || layer == stack.bottom {
			Palette.inactiveCopper
		} else {
			Palette.innerCopper
		}
	}
}
