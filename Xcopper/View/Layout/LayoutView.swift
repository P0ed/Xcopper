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
		let renderer = LayoutRenderer(design: design, state: state, cache: renderCache)
		CanvasScroll(viewport: $state.viewport, size: design.board.size) { isMoving in
			BitmapCanvas(
				key: renderer.key,
				size: design.board.size,
				viewport: state.viewport,
				isMoving: isMoving,
				render: renderer.render
			) { context in
				let scale = state.viewport.magnification
				renderSessions(design.board, in: context, scale: scale, origin: Layout.origin)
				if state.tool != .select {
					renderCursor(state.viewport.cursor, in: context, scale: scale, origin: Layout.origin)
				}
			}
			.contentShape(Rectangle())
			.gesture(editingController)
			.onContinuousHover { phase in
				if case let .active(location) = phase { hover(at: location) }
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
				with: .color(Palette.activeCopper)
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
