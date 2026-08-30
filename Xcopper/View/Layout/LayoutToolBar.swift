import SwiftUI

@MainActor
struct LayoutToolBar: ToolbarContent {
	var stack: Stack
	@Binding var state: LayoutState
	@Binding var sheet: Sheet?

	var body: some ToolbarContent {
		ToolbarItemGroup {
			ForEach(Array(stack.copper), id: \.self) { layer in
				LayerButton(layer: layer, stack: stack, state: $state)
			}
		}
		ToolbarItemGroup { Spacer() }
		ToolbarItemGroup {
			ForEach(Tool.allCases, id: \.self) { tool in
				ToolButton(tool: tool, state: $state.tool)
			}
		}
		ToolbarItemGroup { Spacer() }
		ToolbarItemGroup {
			ActionButton(
				name: "Board",
				image: "square.dashed",
				action: { sheet = .board }
			)
		}
	}
}

@MainActor
struct LayerButton: View {
	var layer: Int
	var stack: Stack
	@Binding
	var state: LayoutState

	private var isActive: Bool { state.layer == layer }

	var body: some View {
		Button(stack.name(of: layer), systemImage: image) { state.layer = layer }
		.foregroundStyle(isActive ? Palette.color(of: layer, in: stack) : .primary)
		.keyboardShortcut(KeyEquivalent(Character("\(layer + 1)")), modifiers: [])
	}

	private var image: String {
		switch layer {
		case stack.top: "t.square"
		case stack.bottom: "b.square"
		default: "\(layer).square"
		}
	}
}
