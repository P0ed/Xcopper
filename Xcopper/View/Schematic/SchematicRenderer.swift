import SwiftUI

@MainActor
struct SchematicRenderer {
	var design: Design
	var state: SchematicState

	private var drawn: (projection: ModuleProjection, selection: Set<Schematic.Ref>) {
		var moved = design
		var selection = state.selection
		if let placement = state.modulePlacement {
			let id = moved.placeModule(placement, at: state.viewport.cursor.snapped(to: state.snap), layout: false)
			selection = [.module(id)]
		}
		if let session = state.moveSession, session.didMove,
			let next = moved.moveSchematic(selection, by: session.delta, grid: state.snap) { selection = next }
		let projection = moved.moduleProjection()
		return (projection, projection.expanded(selection))
	}

	func render(in context: GraphicsContext, scale: CGFloat, visible: CGRect) {
		let origin = Layout.origin
		let (projection, selection) = drawn
		let schematic = projection.design.schematic
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
			visible: visible
		)

		renderWires(schematic, netlist, selection, in: context, scale: scale, origin: origin)
		renderJunctions(schematic, in: context, scale: scale, origin: origin)
		renderSymbols(schematic, selection, in: context, scale: scale, origin: origin)
		renderParameters(projection, in: context, scale: scale, origin: origin)
		renderPins(projection, in: context, scale: scale, origin: origin, visible: visible)
		renderLabels(schematic, netlist, selection, in: context, scale: scale, origin: origin)

		context.stroke(
			Path(schematic.bounds.cg(scale, origin: origin)),
			with: .color(Palette.outline),
			lineWidth: 1.5
		)
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
				radius: max(1.5, Double.mm(400) * scale / 2.0)
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
		let size = 1.2 * scale

		for symbol in schematic.symbols {
			let extent = symbol.placedExtent.cg(scale, origin: origin)

			context.draw(
				Text(symbol.reference)
					.font(.system(size: size, weight: .medium))
					.foregroundStyle(Palette.symbol),
				at: CGPoint(x: extent.midX, y: extent.minY - scale * 0.8)
			)
			if !symbol.value.isEmpty {
				context.draw(
					Text(symbol.value)
						.font(.system(size: size))
						.foregroundStyle(Palette.symbol.opacity(0.7)),
					at: CGPoint(x: extent.midX, y: extent.maxY + scale * 0.8)
				)
			}
		}
	}

	private func renderParameters(
		_ projection: ModuleProjection,
		in context: GraphicsContext,
		scale: CGFloat,
		origin: CGPoint
	) {
		guard scale >= 2.0 else { return }
		let instances = design.modules + (state.modulePlacement.map { [$0.instance] } ?? [])
		let modules = Dictionary(instances.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
		for (ref, id) in projection.symbolOwners {
			guard case let .symbol(index) = ref, let module = modules[id], !module.parameters.isEmpty else { continue }
			let symbol = projection.design.schematic.symbols[index]
			let bounds = module.parameterBounds(in: symbol)
			let center = symbol.place(bounds.center).cg(scale, origin: origin)
			let width = Double.mm(bounds.size.width - 2_540) * scale
			let pitch = 2.54 * scale
			let lines = module.parameterLines
			var context = context
			context.translateBy(x: center.x, y: center.y)
			if symbol.rotation.isQuarter { context.rotate(by: .degrees(-90.0)) }
			let labels = lines.map {
				context.resolve(Text($0).font(.system(size: 1.2 * scale, design: .monospaced)).foregroundStyle(Palette.symbol))
			}
			let widest = labels.map { $0.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity)).width }.max() ?? 0.0
			let fit = min(1.0, width / max(1.0, widest))
			for (row, label) in labels.enumerated() {
				var rowContext = context
				rowContext.translateBy(x: -width / 2.0, y: (Double(row) - Double(lines.count - 1) / 2.0) * pitch)
				rowContext.scaleBy(x: fit, y: fit)
				rowContext.draw(label, at: .zero, anchor: .leading)
			}
		}
	}

	private func renderPins(
		_ projection: ModuleProjection,
		in context: GraphicsContext,
		scale: CGFloat,
		origin: CGPoint,
		visible: CGRect
	) {
		let numberSize = 1.0 * scale
		guard numberSize >= 5.0 else { return }
		let nameSize = Double.mm(PinText.nameHeight) * scale
		let gap = 0.2 * scale
		let inset = 0.4 * scale

		for (index, symbol) in projection.design.schematic.symbols.enumerated() {
			guard symbol.placedExtent.cg(scale, origin: origin).intersects(visible) else { continue }

			let inside = symbol.kind == .ic
			let isModule = projection.symbolOwners[.symbol(index)] != nil
			let numbered = symbol.kind.showsPinNumbers

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
		let size = max(7.0, min(15.0, scale * 1.5))
		let radius = max(1.5, 0.25 * scale)
		let gap = 0.6 * scale

		for (index, symbol) in schematic.symbols.enumerated() {
			let picked = selection.contains(.symbol(index))
			for pin in symbol.placedPins {
				guard let label = pin.netLabel, !label.trimmingWhitespace.isEmpty else { continue }
				let anchor = pin.at.cg(scale, origin: origin)
				let color = pin.hasInvalidIO ? Color.red : color(of: netlist.name(at: pin.at))
				let tint = picked ? Palette.lit(color) : color
				context.fill(
					Path(ellipseIn: CGRect(center: anchor, radius: radius)),
					with: .color(tint)
				)
				guard scale >= 2.0 else { continue }
				let leading = pin.direction == .r0 || pin.direction == .r270
				drawAlongLeg(
					Text(label).font(.system(size: size)).foregroundStyle(tint),
					at: anchor,
					offset: CGPoint(x: leading ? gap : -gap, y: -gap),
					anchor: leading ? .bottomLeading : .bottomTrailing,
					quarter: pin.direction.isQuarter,
					in: context
				)
			}
		}
	}
}

private func renderGrid(
	_ bounds: Rect,
	step: µm,
	in context: GraphicsContext,
	scale: CGFloat,
	origin: CGPoint,
	visible: CGRect
) {
	let step = CGFloat(Double.mm(step)) * scale
	let tileSpan = step * 10.0
	guard step > 0.0, tileSpan >= 3.0 else { return }

	let bounds = bounds.cg(scale, origin: origin)
	let visible = bounds.intersection(visible)
	guard !visible.isNull, !visible.isEmpty else { return }

	let firstColumn = Int(floor((visible.minX - bounds.minX) / tileSpan))
	let lastColumn = Int(floor((visible.maxX - bounds.minX) / tileSpan))
	let firstRow = Int(floor((visible.minY - bounds.minY) / tileSpan))
	let lastRow = Int(floor((visible.maxY - bounds.minY) / tileSpan))
	let columns = lastColumn - firstColumn + 1
	let rows = lastRow - firstRow + 1
	guard columns > 0, rows > 0, columns * rows <= 50_000 else { return }

	let size = min(1.5, max(0.75, step / 12.0))
	let dot = CGRect(center: .zero, radius: size / 2.0)

	var tile = Path()
	for row in 0 ..< 10 {
		for column in 0 ..< 10 where row != 0 || column != 0 {
			tile.addRect(dot.offsetBy(dx: CGFloat(column) * step, dy: CGFloat(row) * step))
		}
	}

	var minor = Path()
	for row in firstRow ... lastRow {
		for column in firstColumn ... lastColumn {
			let x = bounds.minX + CGFloat(column) * tileSpan
			let y = bounds.minY + CGFloat(row) * tileSpan
			minor.addPath(tile, transform: .identity.translatedBy(x: x, y: y))
		}
	}

	var context = context
	context.clip(to: Path(visible))
	context.fill(minor, with: .color(Palette.grid))
}
