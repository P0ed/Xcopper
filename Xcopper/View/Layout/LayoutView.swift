import SwiftUI

@MainActor
struct LayoutView: View {
	@Binding var design: Design
	@Binding var state: LayoutState
	/// Called as a gesture starts, to take the keyboard back from the inspector
	var claimKeyboard: () -> Void = ø

	@Environment(\.undoManager) var undoManager

	var board: Board {
		get { design.board }
		nonmutating set { design.board = newValue }
	}

	var body: some View {
		CanvasScroll(viewport: $state.viewport, size: design.board.size) {
			Canvas { ctx, size in
				render(in: ctx, size: size)
			}
			.gesture(editingController)
			.onContinuousHover { phase in
				if case let .active(location) = phase { hover(at: location) }
			}
		}
		.overlay(alignment: .bottomLeading) { readout }
	}

	private var readout: some View {
		Readout {
			Text(board.stack.name(of: state.layer))
				.foregroundStyle(Palette.color(of: state.layer, in: board.stack))
			Coordinates(cursor: state.viewport.cursor)
			Text("snap \(state.snap.label)")
			Text("grid \(state.grid.label)")
			if state.tool == .trace {
				Text("width \(state.traceWidth.label)")
			}
		}
	}
}
