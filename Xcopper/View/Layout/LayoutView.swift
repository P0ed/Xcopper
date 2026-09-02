import SwiftUI

@MainActor
struct LayoutView: View {
	@Binding var design: Design
	@Binding var state: LayoutState
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
	}
}
