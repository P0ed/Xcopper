import SwiftUI

/// Holds the mode and both editors' state, so switching modes keeps each side's
/// zoom, scroll and selection intact.
@MainActor
struct EditorView: View {
	@Binding var design: Design
	@Binding var clipboard: Clipboard

	@State var editor: EditorState = .init()
	@State var layout: LayoutState = .init()
	@State var schematic: SchematicState = .init()

	@FocusState private(set) var focused: Bool
	@Environment(\.documentConfiguration) private var configuration

	var body: some View {
		NavigationSplitView(
			sidebar: { sidebar },
			detail: { detail }
		)
		.toolbar { toolbar }
		.focusable()
		.focused($focused)
		.focusEffectDisabled()
		.focusedSceneValue(\.operations, operations)
		.onAppear { focused = true }
		.onKeyPress(action: keyboardController)
		.sheet(item: $editor.sheet, content: dialog)
	}

	var operations: Operations {
		Operations(
			editor: $editor,
			layout: $layout,
			schematic: $schematic,
			design: $design,
			clipboard: $clipboard,
			documentName: documentName
		)
	}

	private var documentName: String {
		configuration?.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
	}

	@ViewBuilder
	private var sidebar: some View {
		switch editor.mode {
		case .layout:
			LayoutSideBar(design: $design, state: $layout, sheet: $editor.sheet, operations: operations)
		case .schematic:
			SchematicSideBar(design: $design, state: $schematic, editor: $editor, operations: operations)
		}
	}

	@ViewBuilder
	private var detail: some View {
		switch editor.mode {
		case .layout: LayoutView(design: $design, state: $layout)
		case .schematic: SchematicView(design: $design, state: $schematic)
		}
	}

	@ToolbarContentBuilder
	private var toolbar: some ToolbarContent {
		ToolbarItemGroup { ModePicker(mode: $editor.mode) }
		ToolbarItemGroup { Spacer() }
		if editor.mode == .layout {
			LayoutToolBar(stack: design.board.stack, state: $layout, sheet: $editor.sheet)
		} else {
			SchematicToolBar(state: $schematic, sheet: $editor.sheet, update: operations.updateBoard)
		}
	}

	@ViewBuilder
	private func dialog(_ sheet: Sheet) -> some View {
		switch sheet {
		case .board:
			BoardDialog(
				size: design.board.size,
				stack: design.board.stack,
				loss: design.board.restackLoss
			) { size, stack in
				operations.resize(size: size, stack: stack)
			}
		case .footprint:
			FootprintDialog(spec: $layout.spec) { layout.tool = .footprint }
		case .net:
			NetDialog { name in operations.addNet(name: name) }
		case .symbol:
			SymbolDialog(spec: $schematic.spec) { schematic.tool = .symbol }
		case .label:
			LabelDialog(text: $schematic.label) { schematic.tool = .label }
		}
	}
}
