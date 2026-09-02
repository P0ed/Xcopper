import SwiftUI

@MainActor
struct SchematicView: View {
	@Binding var design: Design
	@Binding var state: SchematicState
	var claimKeyboard: () -> Void = ø

	@Environment(\.undoManager) var undoManager

	var schematic: Schematic {
		get { design.schematic }
		nonmutating set { design.schematic = newValue }
	}

	var body: some View {
		CanvasScroll(viewport: $state.viewport, size: design.schematic.size) {
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
