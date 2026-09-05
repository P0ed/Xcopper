import SwiftUI

extension SchematicView {

	private var drawn: ModuleProjection {
		var moved = design
		if let session = state.moveSession, session.didMove { moved.moveSchematic(state.selection, by: session.delta) }
		return moved.moduleProjection()
	}

	func render(in context: GraphicsContext, size: CGSize) {
		let scale = state.viewport.magnification
		let origin = Layout.origin
		let projection = drawn
		let schematic = projection.design.schematic
		let netlist = Netlist(schematic)
		let selection = projection.expanded(state.selection)
		let visible = state.viewport.visibleRect(in: size)

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
			visible: visible
		)

		renderWires(schematic, netlist, selection, in: context, scale: scale, origin: origin)
		renderJunctions(schematic, in: context, scale: scale, origin: origin)
		renderSymbols(schematic, selection, in: context, scale: scale, origin: origin)
		renderPins(schematic, in: context, scale: scale, origin: origin, visible: visible)
		renderLabels(schematic, netlist, selection, in: context, scale: scale, origin: origin)

		context.stroke(
			Path(schematic.bounds.cg(scale, origin: origin)),
			with: .color(Palette.outline),
			lineWidth: 1.5
		)
		renderSessions(in: context, scale: scale, origin: origin)
		renderCursor(state.viewport.cursor, in: context, scale: scale, origin: origin)
	}

	private func color(of name: String?) -> Color {
		name.map(Palette.color(named:)) ?? Palette.wire
	}

	private func renderWires(
		_ schematic: Schematic,
		_ netlist: Netlist,
		_ selection: Set<Schematic.Ref>,
		in context: GraphicsContext,
		scale: CGFloat,
		origin: CGPoint
	) {
		var picked: [(Path, Color)] = []

		for (index, wire) in schematic.wires.enumerated() {
			var path = Path()
			path.move(to: wire.start.cg(scale, origin: origin))
			path.addLine(to: wire.end.cg(scale, origin: origin))

			let color = color(of: netlist.name(at: wire.start))
			context.stroke(path, with: .color(color), lineWidth: 1.5)
			if selection.contains(.wire(index)) { picked.append((path, Palette.lit(color))) }
		}
		for (path, color) in picked {
			Lit.stroke(path, color, lineWidth: 1.5, in: context)
		}
	}

	private func renderJunctions(
		_ schematic: Schematic,
		in context: GraphicsContext,
		scale: CGFloat,
		origin: CGPoint
	) {
		var path = Path()
		for point in schematic.junctions {
			path.addEllipse(in: CGRect(
				center: point.cg(scale, origin: origin),
				radius: max(1.5, Double(Nm.mm(0.4)).mm * scale / 2.0)
			))
		}
		context.fill(path, with: .color(Palette.junction))
	}

	private func renderSymbols(
		_ schematic: Schematic,
		_ selection: Set<Schematic.Ref>,
		in context: GraphicsContext,
		scale: CGFloat,
		origin: CGPoint
	) {
		var strokes = Path()
		var fills = Path()
		var legs = Path()
		var pickedOutlines = Path()
		var pickedFills = Path()

		for (index, symbol) in schematic.symbols.enumerated() {
			let picked = selection.contains(.symbol(index))

			for shape in symbol.placedGlyph {
				let path = shape.path(scale, origin: origin)
				if shape.isFilled {
					fills.addPath(path)
					if picked { pickedFills.addPath(path) }
				} else {
					strokes.addPath(path)
					if picked { pickedOutlines.addPath(path) }
				}
			}
			for pin in symbol.placedPins {
				var leg = Path()
				leg.move(to: pin.at.cg(scale, origin: origin))
				leg.addLine(to: pin.root.cg(scale, origin: origin))
				legs.addPath(leg)
				if picked { pickedOutlines.addPath(leg) }
			}
		}
		context.stroke(legs, with: .color(Palette.pin), lineWidth: 1.0)
		context.stroke(strokes, with: .color(Palette.symbol), lineWidth: 1.25)
		context.fill(fills, with: .color(Palette.symbol))

		Lit.stroke(pickedOutlines, Palette.lit(Palette.symbol), lineWidth: 1.25, in: context)
		Lit.fill(pickedFills, Palette.lit(Palette.symbol), in: context)

		guard scale >= 2.0 else { return }
		let size = max(7.0, min(15.0, scale * 2.2))

		for symbol in schematic.symbols {
			let extent = symbol.placedExtent.cg(scale, origin: origin)

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

	private func renderPins(
		_ schematic: Schematic,
		in context: GraphicsContext,
		scale: CGFloat,
		origin: CGPoint,
		visible: CGRect
	) {
		let numberSize = Double(PinText.numberHeight).mm * scale
		guard numberSize >= 4.5 else { return }

		let nameSize = Double(PinText.nameHeight).mm * scale
		let gap = Double(PinText.gap).mm * scale
		let inset = Double(PinText.inset).mm * scale

		for symbol in schematic.symbols where !symbol.kind.isPower {
			guard symbol.placedExtent.cg(scale, origin: origin).intersects(visible) else { continue }

			let inside = symbol.kind == .ic
			let isModule = design.modules.contains { $0.reference == symbol.reference }
			let numbered = symbol.kind.showsPinNumbers && !isModule

			for pin in symbol.placedPins {
				let quarter = pin.direction.isQuarter
				let tip = pin.at.cg(scale, origin: origin)
				let root = pin.root.cg(scale, origin: origin)
				let middle = CGPoint(x: (tip.x + root.x) / 2.0, y: (tip.y + root.y) / 2.0)

				if numbered {
					drawAlongLeg(
						Text(pin.number)
							.font(.system(size: numberSize))
							.foregroundStyle(Palette.pin),
						at: middle,
						offset: CGPoint(x: 0.0, y: -gap),
						anchor: .bottom,
						quarter: quarter,
						in: context
					)
				}
				guard pin.isNamed || isModule else { continue }

				let name = Text(pin.name)
					.font(.system(size: nameSize))
					.foregroundStyle(Palette.symbol.opacity(0.85))

				guard inside else {
					drawAlongLeg(
						name,
						at: middle,
						offset: CGPoint(x: 0.0, y: gap),
						anchor: .top,
						quarter: quarter,
						in: context
					)
					continue
				}
				let leading = pin.direction == .r180 || pin.direction == .r90
				drawAlongLeg(
					name,
					at: root,
					offset: CGPoint(x: leading ? inset : -inset, y: 0.0),
					anchor: leading ? .leading : .trailing,
					quarter: quarter,
					in: context
				)
			}
		}
	}

	private func drawAlongLeg(
		_ text: Text,
		at point: CGPoint,
		offset: CGPoint,
		anchor: UnitPoint,
		quarter: Bool,
		in context: GraphicsContext
	) {
		var context = context
		context.translateBy(x: point.x, y: point.y)
		if quarter { context.rotate(by: .degrees(-90.0)) }
		context.draw(text, at: offset, anchor: anchor)
	}

	private func renderLabels(
		_ schematic: Schematic,
		_ netlist: Netlist,
		_ selection: Set<Schematic.Ref>,
		in context: GraphicsContext,
		scale: CGFloat,
		origin: CGPoint
	) {
		guard scale >= 2.0 else { return }
		let size = max(7.0, min(15.0, scale * 2.2))

		for (index, label) in schematic.labels.enumerated() {
			let anchor = label.at.cg(scale, origin: origin)
			let color = color(of: netlist.name(at: label.at))
			let picked = selection.contains(.label(index))

			let text = context.resolve(
				Text(label.text)
					.font(.system(size: size))
					.foregroundStyle(picked ? Palette.lit(color) : color)
			)
			let at = CGPoint(x: anchor.x, y: anchor.y - size)
			if picked {
				let extent = text.measure(in: CGSize(width: 1_000.0, height: 1_000.0))
				Lit.plate(
					CGRect(
						origin: CGPoint(x: at.x, y: at.y - extent.height / 2.0),
						size: extent
					),
					in: context
				)
			}
			context.draw(text, at: at, anchor: .leading)
		}
	}

	private func renderSessions(in context: GraphicsContext, scale: CGFloat, origin: CGPoint) {
		if let session = state.wireSession, session.didDraw {
			var path = Path()
			path.move(to: session.start.cg(scale, origin: origin))
			path.addLine(to: session.end.cg(scale, origin: origin))
			context.stroke(path, with: .color(Palette.preview), lineWidth: 1.5)
		}
		if let session = state.selectSession, session.didDrag {
			marching(Path(session.rect.cg(scale, origin: origin)), in: context)
		}
	}
}
