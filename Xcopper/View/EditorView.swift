import SwiftUI

@MainActor
struct EditorView: View {
	@Binding var design: Design
	@Binding var clipboard: Clipboard

	@State var editor: EditorState = .init()
	@State var layout: LayoutState = .init()
	@State var schematic: SchematicState = .init()
	@State var preview: PreviewState = .init()

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
		.onChange(of: editor.editing) { _, editing in if !editing { focused = true } }
		.onKeyPress(action: keyboardController)
		.sheet(item: $editor.sheet, content: dialog)
	}

	var operations: Operations {
		Operations(
			editor: $editor,
			layout: $layout,
			schematic: $schematic,
			preview: $preview,
			design: $design,
			clipboard: $clipboard,
			documentName: documentName
		)
	}

	private func claimKeyboard() {
		if editor.editing { editor.editing = false }
		guard !focused else { return }
		focused = true
	}

	private var documentName: String {
		configuration?.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
	}

	@ViewBuilder
	private var sidebar: some View {
		switch editor.mode {
		case .layout:
			LayoutSideBar(design: $design, state: $layout, editor: $editor, operations: operations)
		case .schematic:
			SchematicSideBar(design: $design, state: $schematic, editor: $editor, operations: operations)
		case .preview:
			PreviewSideBar(board: design.board, state: $preview)
		}
	}

	@ViewBuilder
	private var detail: some View {
		switch editor.mode {
		case .layout:
			LayoutView(design: $design, state: $layout, claimKeyboard: claimKeyboard)
		case .schematic:
			SchematicView(design: $design, state: $schematic, claimKeyboard: claimKeyboard)
		case .preview: PreviewView(board: design.board, state: $preview)
		}
	}

	@ToolbarContentBuilder
	private var toolbar: some ToolbarContent {
		switch editor.mode {
		case .layout:
			LayoutToolBar(
				stack: design.board.stack,
				state: $layout,
				sheet: $editor.sheet,
				shortcuts: !editor.editing
			)
		case .schematic:
			SchematicToolBar(
				state: $schematic,
				sheet: $editor.sheet,
				shortcuts: !editor.editing,
				update: operations.updateBoard
			)
		case .preview:
			PreviewToolBar(board: design.board, state: $preview)
		}
		ToolbarItemGroup { Spacer() }
		ToolbarItemGroup { ModePicker(mode: $editor.mode) }
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
