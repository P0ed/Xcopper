import SwiftUI

@MainActor
struct SchematicView: View {
	@Binding var design: Design
	@Binding var state: SchematicState
	var claimKeyboard: () -> Void = ø
	var beginEditing: (Property) -> Void = ø

	@Environment(\.undoManager) var undoManager

	var schematic: Schematic {
		get { design.schematic }
		nonmutating set { design.schematic = newValue }
	}

	var body: some View {
		let renderer = SchematicRenderer(design: design, state: state)
		CanvasScroll(viewport: $state.viewport, size: design.schematic.size) {
			ViewportCanvas(viewport: state.viewport) { context, scale, visible in
				renderer.render(in: context, scale: scale, visible: visible)
				renderSessions(in: context, scale: scale, origin: Layout.origin)
				if state.tool != .select || state.modulePlacement != nil {
					let cursor = state.modulePlacement == nil ? state.viewport.cursor : state.viewport.cursor.snapped(to: state.snap)
					renderCursor(cursor, in: context, scale: scale, origin: Layout.origin)
				}
			}
			.contentShape(Rectangle())
			.gesture(editingController)
			.onContinuousHover { phase in
				if case let .active(location) = phase { hover(at: location) }
			}
		}
		.onAppear {
			state.viewport.frame.origin = .zero
		}
	}

	private func renderSessions(in context: GraphicsContext, scale: CGFloat, origin: CGPoint) {
		if let session = state.wireSession, session.didDraw {
			var path = Path()
			path.move(to: session.start.cg(scale, origin: origin))
			for point in session.points.dropFirst() { path.addLine(to: point.cg(scale, origin: origin)) }
			context.stroke(path, with: .color(Palette.preview), lineWidth: 1.5)
		}
		if let session = state.selectSession, session.didDrag {
			marching(Path(session.rect.cg(scale, origin: origin)), in: context)
		}
	}
}

private func marching(_ path: Path, in context: GraphicsContext) {
	context.stroke(path, with: .color(.black), lineWidth: 2.0)
	context.stroke(
		path,
		with: .color(Palette.highlight),
		style: StrokeStyle(lineWidth: 1.0, dash: [4.0, 4.0])
	)
}
