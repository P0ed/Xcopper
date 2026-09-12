import SwiftUI

@MainActor
struct LayoutView: View {
	@Binding var design: Design
	@Binding var state: LayoutState
	var claimKeyboard: () -> Void = ø

	@Environment(\.undoManager) var undoManager
	@State private var renderCache = LayoutRenderCache()

	var board: Board {
		get { design.board }
		nonmutating set { design.board = newValue }
	}

	var body: some View {
		CanvasScroll(viewport: $state.viewport, size: design.board.size) {
			GeometryReader { geo in
				let visible = state.viewport.visibleRect(in: geo.size)
					.insetBy(dx: -128, dy: -128)
					.intersection(CGRect(origin: .zero, size: geo.size))
				if !visible.isNull, !visible.isEmpty {
					Canvas { ctx, _ in
						var ctx = ctx
						ctx.translateBy(x: -visible.minX, y: -visible.minY)
						render(in: ctx, visible: visible)
					}
					.frame(width: visible.width, height: visible.height)
					.offset(x: visible.minX, y: visible.minY)
				}
			}
			.contentShape(Rectangle())
			.gesture(editingController)
			.onContinuousHover { phase in
				if case let .active(location) = phase { hover(at: location) }
			}
		}
	}

	private func render(in context: GraphicsContext, visible: CGRect) {
		let scale = state.viewport.magnification
		let origin = Layout.origin
		let (drawing, picked) = renderCache.value(for: design, state: state)
		let board = drawing.board
		guard !visible.isNull, !visible.isEmpty else { return }
		var context = context
		context.clip(to: Path(visible))
		let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: origin.x, ty: origin.y)
		var geometry = context
		geometry.concatenate(transform)

		renderSubstrate(board, in: context, scale: scale, origin: origin)
		renderGrid(
			board.bounds,
			step: state.grid,
			in: context,
			scale: scale,
			origin: origin,
			visible: visible
		)

		for layer in board.stack.copper where layer != state.layer {
			renderCopper(
				layer,
				drawing,
				picked,
				in: context,
				geometry: geometry,
				transform: transform,
				visible: visible,
				dimmed: true
			)
		}
		renderCopper(
			state.layer,
			drawing,
			picked,
			in: context,
			geometry: geometry,
			transform: transform,
			visible: visible,
			dimmed: false
		)

		geometry.fill(drawing.drills, with: .color(Palette.drill))
		Lit.stroke(picked.drills.applying(transform), Palette.lit(Palette.silk), lineWidth: 1.5, in: context)
		if state.silkscreen {
			renderSilk(board, picked.selection, in: context, scale: scale, origin: origin, visible: visible)
		}
		renderRatsnest(drawing, in: geometry, scale: scale)

		renderModules(drawing.modules, in: context, scale: scale, origin: origin, visible: visible)
		renderOutline(board, in: context, scale: scale, origin: origin)
		renderViolations(drawing.violations, in: context, scale: scale, origin: origin, visible: visible)
		renderSessions(board, in: context, scale: scale, origin: origin)
		if state.tool != .select {
			renderCursor(state.viewport.cursor, in: context, scale: scale, origin: origin)
		}
	}

	private func renderModules(_ modules: [ModuleInstance], in context: GraphicsContext, scale: CGFloat, origin: CGPoint, visible: CGRect) {
		guard state.silkscreen else { return }
		for module in modules {
			let rect = module.bounds.cg(scale, origin: origin)
			let unresolved = design.moduleStatus(module.id) != nil
			let color: Color = unresolved ? .red : Palette.silk
			let label = context.resolve(Text("\(module.reference) · \(unresolved ? "Unresolved" : module.filename)").font(.system(size: 11)).foregroundStyle(color))
			let at = CGPoint(x: rect.midX, y: rect.minY - 10)
			let size = label.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
			if CGRect(x: at.x - size.width / 2, y: at.y - size.height / 2, width: size.width, height: size.height).intersects(visible) {
				context.draw(label, at: at)
			}
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
		_ drawing: LayoutDrawing,
		_ picked: LayoutPickedDrawing,
		in context: GraphicsContext,
		geometry: GraphicsContext,
		transform: CGAffineTransform,
		visible: CGRect,
		dimmed: Bool
	) {
		guard state[visible: layer] else { return }
		let color = Palette.color(of: layer, in: drawing.board.stack)
		let opacity = dimmed ? 0.38 : 1.0

		if let clearances = drawing.clearances[layer] {
			renderPlane(
				drawing.board,
				clearances: clearances,
				in: geometry,
				visible: visible.applying(transform.inverted()),
				color: color.opacity(opacity * 0.30)
			)
		}

		if let path = drawing.copper[layer] {
			geometry.fill(path, with: .color(color.opacity(opacity)))
		}
		if let path = picked.copper[layer] {
			Lit.fill(path.applying(transform), Palette.lit(color).opacity(opacity), in: context)
		}
	}

	private func renderPlane(
		_ board: Board,
		clearances: [Path],
		in context: GraphicsContext,
		visible: CGRect,
		color: Color
	) {
		let inset = Int(board.rules.clearance)
		let bounds = board.bounds.outset(-inset).cg(1, origin: .zero)
		guard bounds.width > 0, bounds.height > 0 else { return }
		let area = bounds.intersection(visible)
		guard !area.isNull, !area.isEmpty else { return }

		context.drawLayer { ctx in
			ctx.fill(Path(area), with: .color(color))
			ctx.blendMode = .destinationOut
			for path in clearances where path.boundingRect.intersects(area) {
				ctx.fill(path, with: .color(.black))
			}
		}
	}

	private func renderRatsnest(
		_ drawing: LayoutDrawing,
		in context: GraphicsContext,
		scale: CGFloat
	) {
		for (net, path) in drawing.ratsnest {
			context.stroke(
				path,
				with: .color(Palette.color(of: net).opacity(0.8)),
				style: StrokeStyle(lineWidth: 0.75 / scale, dash: [3.0 / scale, 3.0 / scale])
			)
		}
	}

	private func renderViolations(
		_ violations: [Point],
		in context: GraphicsContext,
		scale: CGFloat,
		origin: CGPoint,
		visible: CGRect
	) {
		var rings = Path()
		var dots = Path()
		let visible = visible.insetBy(dx: -7, dy: -7)
		for violation in violations {
			let at = violation.cg(scale, origin: origin)
			guard visible.contains(at) else { continue }
			rings.addEllipse(in: CGRect(center: at, radius: 6.0))
			dots.addEllipse(in: CGRect(center: at, radius: 1.25))
		}
		context.stroke(rings, with: .color(Palette.violation), lineWidth: 1.5)
		context.fill(dots, with: .color(Palette.violation))
	}

	private func renderSilk(
		_ board: Board,
		_ selection: Set<Ref>,
		in context: GraphicsContext,
		scale: CGFloat,
		origin: CGPoint,
		visible: CGRect
	) {
		var path = Path()
		var picked = Path()
		for (index, footprint) in board.footprints.enumerated() {
			let body = footprint.placedBody.cg(scale, origin: origin)
			let marker = footprint.place(footprint.pads.first?.at ?? .zero)
				.cg(scale, origin: origin)

			let dot = CGRect(center: marker, radius: max(1.0, scale * 0.12))
			let extent = body.union(dot).insetBy(dx: -Lit.spread, dy: -Lit.spread)
			guard extent.intersects(visible) else { continue }

			var outline = Path()
			if footprint.appearance.stands || footprint.package == .nkkMNPC || footprint.package == .bourns51 || footprint.package == .led5mm {
				outline.addRect(body)
			}
			outline.addEllipse(in: dot)
			if selection.contains(.footprint(index)) {
				picked.addPath(outline)
			} else {
				path.addPath(outline)
			}
		}
		context.stroke(path, with: .color(Palette.silk.opacity(0.5)), lineWidth: 1.0)
		Lit.stroke(picked, Palette.lit(Palette.silk), lineWidth: 1.0, in: context)

		guard scale >= 6.0 else { return }
		for footprint in board.footprints {
			let body = footprint.placedBody.cg(scale, origin: origin)
			let at = CGPoint(x: body.midX, y: body.minY - 7.0)
			guard at.y >= visible.minY - 14, at.y <= visible.maxY + 14 else { continue }
			let label = context.resolve(
				Text(footprint.reference)
					.font(.system(size: max(7.0, min(14.0, scale * 0.7))))
					.foregroundStyle(Palette.silk)
			)
			let size = label.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
			if CGRect(x: at.x - size.width / 2, y: at.y - size.height / 2, width: size.width, height: size.height).intersects(visible) {
				context.draw(label, at: at)
			}
		}
	}

	private func renderSessions(
		_ board: Board,
		in context: GraphicsContext,
		scale: CGFloat,
		origin: CGPoint
	) {
		if let session = state.traceSession, session.didDraw {
			let figure = Figure.segment(session.start, session.end, state.traceWidth ?? board.rules.traceWidth)
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
