import SwiftUI

@MainActor
struct LayoutToolBar: ToolbarContent {
	var stack: Stack
	@Binding var state: LayoutState
	@Binding var sheet: Sheet?
	/// Off while an inspector field has the keyboard
	var shortcuts: Bool = true

	var body: some ToolbarContent {
		ToolbarItemGroup {
			ForEach(Array(stack.copper), id: \.self) { layer in
				LayerButton(layer: layer, stack: stack, state: $state, shortcuts: shortcuts)
			}
		}
		ToolbarItemGroup { Spacer() }
		ToolbarItemGroup {
			ForEach(Tool.allCases, id: \.self) { tool in
				ToolButton(tool: tool, state: $state.tool, shortcuts: shortcuts)
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
	var shortcuts: Bool = true

	private var isActive: Bool { state.layer == layer }

	var body: some View {
		Button(stack.name(of: layer), systemImage: image) { state.layer = layer }
		.foregroundStyle(isActive ? Palette.color(of: layer, in: stack) : .primary)
		.modifier(Shortcut(shortcut: shortcuts ? Character("\(layer + 1)") : nil, modifiers: []))
	}

	private var image: String {
		switch layer {
		case stack.top: "t.square"
		case stack.bottom: "b.square"
		default: "\(layer).square"
		}
	}
}
