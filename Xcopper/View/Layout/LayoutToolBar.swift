import SwiftUI

@MainActor
struct LayoutToolBar: ToolbarContent {
	var stack: Stack
	@Binding var state: LayoutState
	var shortcuts: Bool = true

	var body: some ToolbarContent {
		ToolbarItemGroup {
			ForEach(Tool.allCases, id: \.self) { tool in
				ToolButton(tool: tool, state: $state.tool, shortcuts: shortcuts)
			}
		}
		ToolbarItemGroup { Spacer() }
		ToolbarItemGroup {
			ForEach(Array(stack.signals), id: \.self) { layer in
				LayerButton(
					layer: layer,
					stack: stack,
					state: $state,
					shortcut: shortcuts ? layer == 0 ? "T" : "B" : nil
				)
			}
		}
	}
}

@MainActor
struct LayerButton: View {
	var layer: Int
	var stack: Stack
	@Binding
	var state: LayoutState
	var shortcut: Character?

	private var isActive: Bool { state.layer == layer }

	var body: some View {
		Button(stack.name(of: layer), systemImage: image) { state.layer = layer }
		.foregroundStyle(isActive ? Palette.color(of: layer, in: stack) : .primary)
		.modifier(Shortcut(shortcut: shortcut, modifiers: []))
	}

	private var image: String {
		switch layer {
		case stack.top: "t.square"
		case stack.bottom: "b.square"
		default: "\(layer).square"
		}
	}
}
