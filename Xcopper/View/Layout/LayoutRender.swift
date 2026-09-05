import SwiftUI

extension LayoutView {

	private var drawn: (board: Board, selection: Set<Ref>, modules: [ModuleInstance]) {
		var moved = design
		var selection = state.selection
		if let session = state.moveSession, session.didMove,
			let next = moved.moveLayout(selection, by: session.delta, grid: state.snap) { selection = next }
		let projection = moved.moduleProjection()
		return (projection.design.board, projection.expanded(selection), moved.modules)
	}

	func render(in context: GraphicsContext, size: CGSize) {
		let scale = state.viewport.magnification
		let origin = Layout.origin
		let (board, selection, modules) = drawn

		renderSubstrate(board, in: context, scale: scale, origin: origin)
		renderGrid(
			board.bounds,
			step: state.grid,
			in: context,
			scale: scale,
			origin: origin,
			visible: state.viewport.visibleRect(in: size)
		)

		for layer in board.stack.copper where layer != state.layer {
			renderCopper(
				layer,
				of: board,
				selection,
				in: context,
				scale: scale,
				origin: origin,
				dimmed: true
			)
		}
		renderCopper(
			state.layer,
			of: board,
			selection,
			in: context,
			scale: scale,
			origin: origin,
			dimmed: false
		)

		renderDrills(board, selection, in: context, scale: scale, origin: origin)
		renderSilk(board, selection, in: context, scale: scale, origin: origin)
		renderRatsnest(board, in: context, scale: scale, origin: origin)

		renderModules(modules, in: context, scale: scale, origin: origin)
		renderOutline(board, in: context, scale: scale, origin: origin)
		renderViolations(board, in: context, scale: scale, origin: origin)
		renderSessions(board, in: context, scale: scale, origin: origin)
		renderCursor(state.viewport.cursor, in: context, scale: scale, origin: origin)
	}

	private func renderModules(_ modules: [ModuleInstance], in context: GraphicsContext, scale: CGFloat, origin: CGPoint) {
		for module in modules {
			let unresolved = design.moduleStatus(module.id) != nil
			let color: Color = unresolved ? .red : state.selection.contains(.module(module.id)) ? Palette.preview : Palette.silk
			let rect = module.bounds.cg(scale, origin: origin)
			context.stroke(Path(rect), with: .color(color), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
			context.draw(Text("\(module.reference) · \(unresolved ? "Unresolved" : module.filename)").font(.system(size: 11)).foregroundStyle(color), at: CGPoint(x: rect.midX, y: rect.minY - 10))
		}
	}

	private func renderSubstrate(
		_ board: Board,
		in context: GraphicsContext,
		scale: CGFloat,
		origin: CGPoint
	) {
		context.fill(Path(board.bounds.cg(scale, origin: origin)), with: .color(Palette.substrate))
	}

	private func renderOutline(
		_ board: Board,
		in context: GraphicsContext,
		scale: CGFloat,
		origin: CGPoint
	) {
		context.stroke(
			Path(board.bounds.cg(scale, origin: origin)),
			with: .color(Palette.outline),
			lineWidth: 1.5
		)
	}

	private func renderCopper(
		_ layer: Int,
		of board: Board,
		_ selection: Set<Ref>,
		in context: GraphicsContext,
		scale: CGFloat,
		origin: CGPoint,
		dimmed: Bool
	) {
		let color = Palette.color(of: layer, in: board.stack)
		let opacity = dimmed ? 0.38 : 1.0

		if let plane = design.plane(layer) {
			renderPlane(
				layer,
				of: board,
				net: plane,
				in: context,
				scale: scale,
				origin: origin,
				color: color.opacity(opacity * 0.30)
			)
		}

		var path = Path()
		for (figure, _) in board.figures(on: layer) {
			path.addPath(figure.path(scale, origin: origin))
		}
		context.fill(path, with: .color(color.opacity(opacity)))

		var picked = Path()
		for figure in board.figures(on: layer, of: selection) {
			picked.addPath(figure.path(scale, origin: origin))
		}
		Lit.fill(picked, Palette.lit(color).opacity(opacity), in: context)
	}

	private func renderPlane(
		_ layer: Int,
		of board: Board,
		net: Net.ID,
		in context: GraphicsContext,
		scale: CGFloat,
		origin: CGPoint,
		color: Color
	) {
		let inset = Int(board.rules.clearance)
		let area = board.bounds.outset(-inset).cg(scale, origin: origin)
		guard area.width > 0.0, area.height > 0.0 else { return }

		context.drawLayer { ctx in
			ctx.fill(Path(area), with: .color(color))
			ctx.blendMode = .destinationOut
			for figure in board.clearances(on: layer, net: net) {
				ctx.fill(figure.path(scale, origin: origin), with: .color(.black))
			}
		}
	}

	private func renderRatsnest(
		_ board: Board,
		in context: GraphicsContext,
		scale: CGFloat,
		origin: CGPoint
	) {
		for rat in board.ratsnest(planes: design.planes) {
			var path = Path()
			path.move(to: rat.from.cg(scale, origin: origin))
			path.addLine(to: rat.to.cg(scale, origin: origin))
			context.stroke(
				path,
				with: .color(Palette.color(of: rat.net).opacity(0.8)),
				style: StrokeStyle(lineWidth: 0.75, dash: [3.0, 3.0])
			)
		}
	}

	private func renderViolations(
		_ board: Board,
		in context: GraphicsContext,
		scale: CGFloat,
		origin: CGPoint
	) {
		var rings = Path()
		var dots = Path()
		for violation in modifying(Design(board: board), { $0.nets = design.resolved.nets }).faults() {
			let at = violation.at.cg(scale, origin: origin)
			rings.addEllipse(in: CGRect(center: at, radius: 6.0))
			dots.addEllipse(in: CGRect(center: at, radius: 1.25))
		}
		context.stroke(rings, with: .color(Palette.violation), lineWidth: 1.5)
		context.fill(dots, with: .color(Palette.violation))
	}

	private func renderDrills(
		_ board: Board,
		_ selection: Set<Ref>,
		in context: GraphicsContext,
		scale: CGFloat,
		origin: CGPoint
	) {
		var path = Path()
		for figure in board.drills {
			path.addPath(figure.path(scale, origin: origin))
		}
		context.fill(path, with: .color(Palette.drill))

		var picked = Path()
		for case let .hole(index) in selection where board.holes.indices.contains(index) {
			let hole = board.holes[index]
			picked.addPath(Figure.round(hole.at, hole.diameter).path(scale, origin: origin))
		}
		Lit.stroke(picked, Palette.lit(Palette.silk), lineWidth: 1.5, in: context)
	}

	private func renderSilk(
		_ board: Board,
		_ selection: Set<Ref>,
		in context: GraphicsContext,
		scale: CGFloat,
		origin: CGPoint
	) {
		var path = Path()
		var picked = Path()
		for (index, footprint) in board.footprints.enumerated() {
			let body = footprint.placedBody.cg(scale, origin: origin)
			let marker = footprint.place(footprint.pads.first?.at ?? .zero)
				.cg(scale, origin: origin)

			var outline = Path()
			if footprint.package.stands {
				outline.addRect(body)
			}
			outline.addEllipse(in: CGRect(center: marker, radius: max(1.0, scale * 0.12)))
			if selection.contains(.footprint(index)) {
				picked.addPath(outline)
			} else {
				path.addPath(outline)
			}
		}
		context.stroke(path, with: .color(Palette.silk.opacity(0.55)), lineWidth: 1.0)
		Lit.stroke(picked, Palette.lit(Palette.silk), lineWidth: 1.0, in: context)

		guard scale >= 6.0 else { return }
		for footprint in board.footprints {
			let body = footprint.placedBody.cg(scale, origin: origin)
			context.draw(
				Text(footprint.reference)
					.font(.system(size: max(7.0, min(14.0, scale * 0.7))))
					.foregroundStyle(Palette.silk),
				at: CGPoint(x: body.midX, y: body.minY - 7.0)
			)
		}
	}

	private func renderSessions(
		_ board: Board,
		in context: GraphicsContext,
		scale: CGFloat,
		origin: CGPoint
	) {
		if let session = state.traceSession, session.didDraw {
			let figure = Figure.segment(session.start, session.end, state.traceWidth)
			context.fill(
				figure.path(scale, origin: origin),
				with: .color(Palette.color(of: session.layer, in: board.stack).opacity(0.7))
			)
			context.stroke(
				figure.path(scale, origin: origin),
				with: .color(Palette.preview),
				lineWidth: 0.75
			)
		}
		if let session = state.selectSession, session.didDrag {
			marching(Path(session.rect.cg(scale, origin: origin)), in: context)
		}
	}
}
