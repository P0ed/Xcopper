import SwiftUI

@MainActor
struct SchematicSideBar: View {
	@Binding var design: Design
	@Binding var state: SchematicState
	@Binding var editor: EditorState
	var operations: Operations

	@FocusState private var focus: Property?

	private var netlist: Netlist { Netlist(design.resolved.schematic) }

	var body: some View {
		ScrollView(.vertical) {
			VStack(alignment: .leading, spacing: 12.0) {
				Panel(title: "Selection") {
					if state.selection.count == 1, let id = state.selection.moduleIDs.first {
						ModuleInspector(design: $design, id: id, layout: false, focus: $focus)
					} else {
						SchematicInspector(
							design: $design,
							netlist: netlist,
							selection: state.selection,
							focus: $focus
						)
					}
					CounterpartButton(operations: operations)
				}

				ModulePanel(operations: operations)

				Panel(title: "Sheet") {
					GridPicker(title: "Snap", value: $state.snap, options: µm.sheetSnapGrids)
					GridPicker(title: "Grid", value: $state.grid, options: µm.displayGrids)
				}

				Panel(title: "Place") {
					Button("Symbol…", systemImage: "square.on.circle") { editor.sheet = .symbol }
						.buttonStyle(.borderless)
					Text(state.spec.summary)
						.font(.caption)
						.foregroundStyle(.secondary)
					Button("Label…", systemImage: "tag") { editor.sheet = .label }
						.buttonStyle(.borderless)
						.padding(.top, 2.0)
					Text(state.label)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
			.padding(12.0)
		}
		.navigationSplitViewColumnWidth(min: 190.0, ideal: 230.0, max: 300.0)
		.onChange(of: focus) { _, field in editor.editing = field }
		.onChange(of: editor.editing) { _, editing in focus = editing }
		.onDisappear { editor.editing = nil }
	}
}
