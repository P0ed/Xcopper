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
			LayerToggle(
				name: "Silk",
				image: "textformat",
				bit: LayoutState.silkBit,
				state: $state
			)
			LayerToggle(
				name: "Drills",
				image: "circle.dotted",
				bit: LayoutState.drillBit,
				state: $state
			)
			LayerToggle(
				name: "Ratsnest",
				image: "point.3.filled.connected.trianglepath.dotted",
				bit: LayoutState.ratsBit,
				state: $state
			)
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

	private var isVisible: Bool { state.isVisible(layer) }
	private var isActive: Bool { state.layer == layer }

	var body: some View {
		Button(stack.name(of: layer), systemImage: image) {
			if isActive {
				state.toggleVisible(layer)
			} else {
				state.layer = layer
			}
		}
		.foregroundStyle(isActive ? Palette.color(of: layer, in: stack) : .primary)
		.opacity(isVisible ? 1.0 : 0.4)
		.keyboardShortcut(KeyEquivalent(Character("\(layer + 1)")), modifiers: [])
	}

	private var image: String {
		switch layer {
		case stack.top: "t.square\(isVisible ? ".fill" : "")"
		case stack.bottom: "b.square\(isVisible ? ".fill" : "")"
		default: "\(layer).square\(isVisible ? ".fill" : "")"
		}
	}
}

@MainActor
struct LayerToggle: View {
	var name: String
	var image: String
	var bit: Int
	@Binding
	var state: LayoutState

	private var isVisible: Bool { state.visibleLayers & 1 << bit != 0 }

	var body: some View {
		Button(name, systemImage: image) { state.toggleVisible(bit) }
			.foregroundStyle(isVisible ? .primary : .tertiary)
	}
}
