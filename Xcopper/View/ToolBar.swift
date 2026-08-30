import SwiftUI

extension EditorView {

	@ToolbarContentBuilder
	var toolbar: some ToolbarContent {
		ToolbarItemGroup {
			ForEach(Array(board.stack.copper), id: \.self) { layer in
				LayerButton(layer: layer, stack: board.stack, state: $state)
			}
			LayerToggle(
				name: "Silk",
				image: "textformat",
				bit: EditorState.silkBit,
				state: $state
			)
			LayerToggle(
				name: "Drills",
				image: "circle.dotted",
				bit: EditorState.drillBit,
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
				action: { state.boardDialogPresented = true }
			)
		}
	}
}

@MainActor
struct ToolButton: View {
	var tool: Tool
	@Binding
	var state: Tool

	var body: some View {
		Button(tool.actionName, systemImage: tool.systemImage, action: { state = tool })
			.foregroundStyle(state == tool ? Color.accentColor : .primary)
			.keyboardShortcut(KeyEquivalent(tool.shortcutCharacter), modifiers: [])
	}
}

@MainActor
struct ActionButton: View {
	var name: String
	var image: String
	var shortcut: Character?
	var modifiers: EventModifiers = []
	var disabled: Bool = false
	var action: () -> Void

	var body: some View {
		Button(name, systemImage: image, action: action)
			.disabled(disabled)
			.modifier(Shortcut(shortcut: shortcut, modifiers: modifiers))
	}
}

@MainActor
private struct Shortcut: ViewModifier {
	var shortcut: Character?
	var modifiers: EventModifiers

	func body(content: Content) -> some View {
		if let shortcut {
			content.keyboardShortcut(KeyEquivalent(shortcut), modifiers: modifiers)
		} else {
			content
		}
	}
}

@MainActor
struct LayerButton: View {
	var layer: Int
	var stack: Stack
	@Binding
	var state: EditorState

	private var name: String { stack.shortName(of: layer) }
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
	var state: EditorState

	private var isVisible: Bool { state.visibleLayers & 1 << bit != 0 }

	var body: some View {
		Button(name, systemImage: image) { state.toggleVisible(bit) }
			.foregroundStyle(isVisible ? .primary : .tertiary)
	}
}
