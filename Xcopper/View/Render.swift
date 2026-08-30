import SwiftUI

enum Layout {
	static let margin: CGFloat = 24.0
	static let origin = CGPoint(x: margin, y: margin)

	static func contentSize(_ board: Board, scale: CGFloat) -> CGSize {
		let size = board.size.cg * scale
		return CGSize(width: size.width + margin * 2.0, height: size.height + margin * 2.0)
	}

	static func point(_ location: CGPoint, scale: CGFloat) -> Pt {
		Pt(
			x: Int(((location.x - margin) / scale * 1_000_000.0).rounded()),
			y: Int(((location.y - margin) / scale * 1_000_000.0).rounded())
		)
	}
}

extension EditorView {

	func render(in context: GraphicsContext, size: CGSize) {
		let scale = state.magnification
		let origin = Layout.origin

		renderSubstrate(in: context, scale: scale, origin: origin)
		renderGrid(in: context, scale: scale, origin: origin)

		let layers = board.stack.copper.filter { state.isVisible($0) }
		for layer in layers where layer != state.layer {
			renderCopper(layer, in: context, scale: scale, origin: origin, dimmed: true)
		}
		if layers.contains(state.layer) {
			renderCopper(state.layer, in: context, scale: scale, origin: origin, dimmed: false)
		}

		if state.drillVisible { renderDrills(in: context, scale: scale, origin: origin) }
		if state.silkVisible { renderSilk(in: context, scale: scale, origin: origin) }

		renderOutline(in: context, scale: scale, origin: origin)
		renderSessions(in: context, scale: scale, origin: origin)
		renderSelection(in: context, scale: scale, origin: origin)
		renderCursor(in: context, scale: scale, origin: origin)
	}

	private func renderCursor(in context: GraphicsContext, scale: CGFloat, origin: CGPoint) {
		let center = state.cursor.cg(scale, origin: origin)
		let arm = 6.0
		var path = Path()
		path.move(to: CGPoint(x: center.x - arm, y: center.y))
		path.addLine(to: CGPoint(x: center.x + arm, y: center.y))
		path.move(to: CGPoint(x: center.x, y: center.y - arm))
		path.addLine(to: CGPoint(x: center.x, y: center.y + arm))
		context.stroke(path, with: .color(Palette.preview), lineWidth: 1.0)
	}

	private func renderSubstrate(in context: GraphicsContext, scale: CGFloat, origin: CGPoint) {
		context.fill(Path(board.bounds.cg(scale, origin: origin)), with: .color(Palette.substrate))
	}

	private func renderGrid(in context: GraphicsContext, scale: CGFloat, origin: CGPoint) {
		let step = Double(state.grid).mm * scale
		guard step >= 5.0 else { return }

		let bounds = board.bounds.cg(scale, origin: origin)
		let dot = min(1.5, max(0.75, step / 12.0))
		var path = Path()

		var y = bounds.minY
		while y <= bounds.maxY + 0.5 {
			var x = bounds.minX
			while x <= bounds.maxX + 0.5 {
				path.addEllipse(in: CGRect(center: CGPoint(x: x, y: y), radius: dot / 2.0))
				x += step
			}
			y += step
		}
		context.fill(path, with: .color(Palette.grid))
	}

	private func renderOutline(in context: GraphicsContext, scale: CGFloat, origin: CGPoint) {
		context.stroke(
			Path(board.bounds.cg(scale, origin: origin)),
			with: .color(Palette.outline),
			lineWidth: 1.5
		)
	}

	private func renderCopper(
		_ layer: Int,
		in context: GraphicsContext,
		scale: CGFloat,
		origin: CGPoint,
		dimmed: Bool
	) {
		let color = Palette.color(of: layer, in: board.stack)
		let opacity = dimmed ? 0.38 : 1.0

		if let plane = board.plane(layer) {
			renderPlane(
				layer,
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
	}

	private func renderPlane(
		_ layer: Int,
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

	private func renderDrills(in context: GraphicsContext, scale: CGFloat, origin: CGPoint) {
		var path = Path()
		for figure in board.drills {
			path.addPath(figure.path(scale, origin: origin))
		}
		context.fill(path, with: .color(Palette.drill))
	}

	private func renderSilk(in context: GraphicsContext, scale: CGFloat, origin: CGPoint) {
		var path = Path()
		for footprint in board.footprints {
			let body = footprint.placedBody.cg(scale, origin: origin)
			path.addRect(body)
			let marker = footprint.place(footprint.pads.first?.at ?? .zero)
				.cg(scale, origin: origin)
			path.addEllipse(in: CGRect(center: marker, radius: max(1.0, scale * 0.12)))
		}
		context.stroke(path, with: .color(Palette.silk.opacity(0.55)), lineWidth: 1.0)

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

	private func renderSessions(in context: GraphicsContext, scale: CGFloat, origin: CGPoint) {
		if let session = state.traceSession, session.start != session.end {
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

	private func renderSelection(in context: GraphicsContext, scale: CGFloat, origin: CGPoint) {
		let delta = state.moveSession?.delta ?? .zero
		var path = Path()
		for ref in state.selection {
			guard let bounds = board.bounds(of: [ref]) else { continue }
			path.addRect(bounds.offset(by: delta).outset(Int(Nm.mm(0.1))).cg(scale, origin: origin))
		}
		guard !path.isEmpty else { return }
		marching(path, in: context)
	}

	private func marching(_ path: Path, in context: GraphicsContext) {
		context.stroke(path, with: .color(.black), lineWidth: 2.0)
		context.stroke(
			path,
			with: .color(Palette.highlight),
			style: StrokeStyle(lineWidth: 1.0, dash: [4.0, 4.0])
		)
	}
}
