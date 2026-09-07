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
	@Environment(\.undoManager) private var undoManager

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
		.onChange(of: configuration?.fileURL, initial: true) { _, _ in
			undoManager?.disableUndoRegistration()
			defer { undoManager?.enableUndoRegistration() }
			operations.reloadModules(automatic: true)
		}
		.onChange(of: editor.editing) { _, editing in if editing == nil { focused = true } }
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
			documentURL: configuration?.fileURL,
			documentName: documentName
		)
	}

	private func claimKeyboard() {
		if editor.editing != nil { editor.editing = nil }
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
			PreviewSideBar(board: design.resolved.board, state: $preview)
		}
	}

	@ViewBuilder
	private var detail: some View {
		switch editor.mode {
		case .layout:
			LayoutView(design: $design, state: $layout, claimKeyboard: claimKeyboard)
		case .schematic:
			SchematicView(
				design: $design,
				state: $schematic,
				claimKeyboard: claimKeyboard,
				beginEditing: { property in editor.editing = property }
			)
		case .preview: PreviewView(board: design.resolved.board, state: $preview)
		}
	}

	@ToolbarContentBuilder
	private var toolbar: some ToolbarContent {
		switch editor.mode {
		case .layout:
			LayoutToolBar(
				stack: design.board.stack,
				state: $layout,
				shortcuts: editor.editing == nil
			)
		case .schematic:
			SchematicToolBar(
				state: $schematic,
				shortcuts: editor.editing == nil
			)
		case .preview:
			PreviewToolBar(board: design.resolved.board, state: $preview)
		}
		ToolbarItemGroup { Spacer() }
		ToolbarItemGroup { ModePicker(mode: $editor.mode) }
	}

	@ViewBuilder
	private func dialog(_ sheet: Sheet) -> some View {
		switch sheet {
		case .board:
			BoardDialog(size: design.board.size, stack: design.board.stack) { size, stack in
				operations.resize(size: size, stack: stack)
			}
		case .schematic:
			SchematicDialog(size: design.schematic.size) { size in
				operations.resizeSheet(size: size)
			}
		case .footprint:
			FootprintDialog(spec: $layout.spec) { layout.tool = .footprint }
		case .net:
			NetDialog { name in operations.addNet(name: name) }
		case .symbol:
			SymbolDialog(spec: $schematic.spec) { schematic.tool = .symbol }
		case .label:
			LabelDialog(text: $schematic.label) { schematic.tool = .label }
		case .find:
			PromptDialog(action: "Find", prompt: "Reference or value", text: $editor.query) { query in
				operations.find(query)
			}
		}
	}
}
