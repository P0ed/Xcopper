import SwiftUI

@MainActor
struct SchematicView: View {
	@Binding var design: Design
	@Binding var state: SchematicState

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
		.overlay(alignment: .bottomLeading) { readout }
	}

	private var readout: some View {
		Readout {
			Text(state.tool.actionName)
				.foregroundStyle(Palette.wire)
			Coordinates(cursor: state.viewport.cursor)
			Text("grid \(state.grid.label)")
			if state.tool == .label {
				Text("label \(state.label)")
			}
		}
	}
}
