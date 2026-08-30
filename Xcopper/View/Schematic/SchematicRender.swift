import SwiftUI

extension SchematicView {

	func render(in context: GraphicsContext, size: CGSize) {
		let scale = state.viewport.magnification
		let origin = Layout.origin
		let netlist = Netlist(schematic)

		context.fill(
			Path(schematic.bounds.cg(scale, origin: origin)),
			with: .color(Palette.sheet)
		)
		renderGrid(
			schematic.bounds,
			step: state.grid,
			in: context,
			scale: scale,
			origin: origin,
			visible: state.viewport.visibleRect(in: size)
		)

		renderWires(netlist, in: context, scale: scale, origin: origin)
		renderJunctions(in: context, scale: scale, origin: origin)
		renderSymbols(in: context, scale: scale, origin: origin)
		renderLabels(netlist, in: context, scale: scale, origin: origin)

		context.stroke(
			Path(schematic.bounds.cg(scale, origin: origin)),
			with: .color(Palette.outline),
			lineWidth: 1.5
		)
		renderSessions(in: context, scale: scale, origin: origin)
		renderSelection(in: context, scale: scale, origin: origin)
		renderCursor(state.viewport.cursor, in: context, scale: scale, origin: origin)
	}

	private func color(of name: String?) -> Color {
		name.map(Palette.color(named:)) ?? Palette.wire
	}

	private func renderWires(
		_ netlist: Netlist,
		in context: GraphicsContext,
		scale: CGFloat,
		origin: CGPoint
	) {
		for wire in schematic.wires {
			var path = Path()
			path.move(to: wire.start.cg(scale, origin: origin))
			path.addLine(to: wire.end.cg(scale, origin: origin))
			context.stroke(
				path,
				with: .color(color(of: netlist.name(at: wire.start))),
				lineWidth: 1.5
			)
		}
	}

	private func renderJunctions(in context: GraphicsContext, scale: CGFloat, origin: CGPoint) {
		var path = Path()
		for point in schematic.junctions {
			path.addEllipse(in: CGRect(
				center: point.cg(scale, origin: origin),
				radius: max(1.5, Double(Nm.mm(0.4)).mm * scale / 2.0)
			))
		}
		context.fill(path, with: .color(Palette.junction))
	}

	private func renderSymbols(in context: GraphicsContext, scale: CGFloat, origin: CGPoint) {
		var strokes = Path()
		var fills = Path()
		var legs = Path()

		for symbol in schematic.symbols {
			for shape in symbol.placedGlyph {
				if shape.isFilled {
					fills.addPath(shape.path(scale, origin: origin))
				} else {
					strokes.addPath(shape.path(scale, origin: origin))
				}
			}
			for pin in symbol.placedPins {
				legs.move(to: pin.at.cg(scale, origin: origin))
				legs.addLine(to: pin.root.cg(scale, origin: origin))
			}
		}
		context.stroke(legs, with: .color(Palette.pin), lineWidth: 1.0)
		context.stroke(strokes, with: .color(Palette.symbol), lineWidth: 1.25)
		context.fill(fills, with: .color(Palette.symbol))

		guard scale >= 2.0 else { return }
		let size = max(7.0, min(15.0, scale * 2.2))

		for symbol in schematic.symbols {
			let extent = symbol.placedExtent.cg(scale, origin: origin)

			// A power flag has no designator worth showing, only the net it names
			if symbol.kind.isPower {
				context.draw(
					Text(symbol.value)
						.font(.system(size: size))
						.foregroundStyle(Palette.color(named: symbol.value)),
					at: CGPoint(
						x: extent.midX,
						y: symbol.kind == .ground ? extent.maxY + size : extent.minY - size
					)
				)
				continue
			}
			context.draw(
				Text(symbol.reference)
					.font(.system(size: size, weight: .medium))
					.foregroundStyle(Palette.symbol),
				at: CGPoint(x: extent.midX, y: extent.minY - size * 0.7)
			)
			if !symbol.value.isEmpty {
				context.draw(
					Text(symbol.value)
						.font(.system(size: size))
						.foregroundStyle(Palette.symbol.opacity(0.7)),
					at: CGPoint(x: extent.midX, y: extent.maxY + size * 0.7)
				)
			}
		}
	}

	private func renderLabels(
		_ netlist: Netlist,
		in context: GraphicsContext,
		scale: CGFloat,
		origin: CGPoint
	) {
		guard scale >= 2.0 else { return }
		let size = max(7.0, min(15.0, scale * 2.2))

		for label in schematic.labels {
			let anchor = label.at.cg(scale, origin: origin)
			context.draw(
				Text(label.text)
					.font(.system(size: size))
					.foregroundStyle(color(of: netlist.name(at: label.at))),
				at: CGPoint(x: anchor.x, y: anchor.y - size),
				anchor: .leading
			)
		}
	}

	private func renderSessions(in context: GraphicsContext, scale: CGFloat, origin: CGPoint) {
		if let session = state.wireSession, session.start != session.end {
			var path = Path()
			path.move(to: session.start.cg(scale, origin: origin))
			path.addLine(to: session.end.cg(scale, origin: origin))
			context.stroke(path, with: .color(Palette.preview), lineWidth: 1.5)
		}
		if let session = state.selectSession, session.didDrag {
			marching(Path(session.rect.cg(scale, origin: origin)), in: context)
		}
	}

	private func renderSelection(in context: GraphicsContext, scale: CGFloat, origin: CGPoint) {
		let delta = state.moveSession?.delta ?? .zero
		var path = Path()

		for ref in state.selection {
			guard let bounds = schematic.bounds(of: [ref]) else { continue }
			path.addRect(bounds.offset(by: delta).outset(Int(Nm.mm(0.4))).cg(scale, origin: origin))
		}
		guard !path.isEmpty else { return }
		marching(path, in: context)
	}
}
