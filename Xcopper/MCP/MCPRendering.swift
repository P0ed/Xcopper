import AppKit
import MCP
import SwiftUI

@MainActor
extension MCPTools {
	static func renderDesign(_ args: MCPArguments, entry: MCPDocumentEntry) throws -> MCPJSON {
		entry.refresh()
		let design = try args.values["proposalId"]?.stringValue.map { try connectionProposal($0, entry: entry).1.candidate } ?? entry.design
		let view = try args.string("view")
		let width = args.values["width"]?.intValue ?? 1024
		let height = args.values["height"]?.intValue ?? 1024
		let bounds: Rect
		if args.values["bounds"] != nil {
			let supplied = try args.object("bounds")
			bounds = try Rect(origin: supplied.point("origin"), size: supplied.size("size"))
		} else { bounds = view == "layout" ? design.board.bounds : design.board.sheetBounds }
		guard !bounds.size.isEmpty else { throw MCPFailure("invalid_geometry", "Preview bounds must have positive dimensions.") }
		let layers = args.values["layers"]?.arrayValue?.compactMap(\.intValue) ?? design.board.stack.signals
		guard layers.allSatisfy(design.board.stack.contains) else { throw MCPFailure("invalid_layer", "Preview layers must belong to this board stack.") }
		let pixels = CGSize(width: width, height: height)
		let scale = min(Double(width) / Double.mm(bounds.size.width), Double(height) / Double.mm(bounds.size.height)) * 0.96
		let offset = CGPoint(x: (Double(width) - Double.mm(bounds.size.width) * scale) / 2 - Double.mm(bounds.minX) * scale,
			y: (Double(height) - Double.mm(bounds.size.height) * scale) / 2 - Double.mm(bounds.minY) * scale)
		var state = LayoutState(stack: design.board.stack)
		state.viewport.resize(to: pixels, content: design.board.size)
		state.viewport.setScale(scale)
		for layer in design.board.stack.copper { state[visible: layer] = layers.contains(layer) }
		state.layer = layers.last ?? design.board.stack.top
		state.ratsnest = args.values["ratsnest"] == true
		state.silkscreen = args.values["silkscreen"] != false
		let renderer = LayoutRenderer(design: design, state: state)
		let pieces = view == "layout" ? [renderer.copper(state), renderer.silkscreen(state, selection: []), renderer.connections(state), renderer.outline(state)]
			.flatMap(\.pieces).sorted { $0.level < $1.level } : []
		let content = Canvas { context, _ in
			context.fill(Path(CGRect(origin: .zero, size: pixels)), with: .color(view == "layout" ? Palette.background : Palette.sheet))
			if view == "schematic" {
				var context = context
				context.translateBy(x: offset.x - Layout.origin.x, y: offset.y - Layout.origin.y)
				var state = SchematicState()
				state.grid = 0
				SchematicRenderer(design: design, state: state).render(in: context, scale: scale, visible: CGRect(x: -offset.x, y: -offset.y, width: Double(width), height: Double(height)))
			} else {
				for piece in pieces {
					var path = Path()
					for loop in [piece.loop] + piece.holes {
						guard let first = loop.first else { continue }
						path.move(to: CGPoint(x: first.x * scale + offset.x, y: first.y * scale + offset.y))
						for point in loop.dropFirst() { path.addLine(to: CGPoint(x: point.x * scale + offset.x, y: point.y * scale + offset.y)) }
						path.closeSubpath()
					}
					context.fill(path, with: .color(piece.shade.rgb(Finish()).color), style: FillStyle(eoFill: true))
				}
			}
		}.frame(width: pixels.width, height: pixels.height)
		let imageRenderer = ImageRenderer(content: content)
		imageRenderer.scale = 1
		guard let image = imageRenderer.cgImage, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw MCPFailure("render_failed", "The native design preview could not be rendered.") }
		return ["documentId": .string(entry.id.uuidString), "revision": .int(entry.revision), "proposalId": args.values["proposalId"] ?? .null, "view": .string(view), "bounds": try MCPJSON(bounds), "layers": .array(layers.map { .int($0) }), "width": .int(width), "height": .int(height), "units": "micrometres", "imageData": .string(png.base64EncodedString())]
	}
}
