import SwiftUI

@MainActor
struct SchematicSideBar: View {
	@Binding var design: Design
	@Binding var state: SchematicState
	@Binding var editor: EditorState
	var operations: Operations

	@FocusState private var focus: Property?

	private var netlist: Netlist { Netlist(design.moduleProjection().sheet) }

	var body: some View {
		ScrollView(.vertical) {
			VStack(alignment: .leading, spacing: 12.0) {
				if state.selection.isEmpty && state.modulePlacement == nil {
					ParametersPanel(design: $design, focus: $focus)
				} else {
					selectionPanel
				}
				Panel(title: "Sheet") {
					ValuePicker(title: "Snap", value: $state.snap, options: µm.sheetSnapGrids)
					ValuePicker(title: "Grid", value: $state.grid, options: µm.displayGrids)
				}
				ModulePanel(operations: operations)
			}
			.padding(12.0)
		}
		.navigationSplitViewColumnWidth(min: 190.0, ideal: 230.0, max: 300.0)
		.onChange(of: focus) { _, field in editor.editing = field }
		.onChange(of: editor.editing) { _, editing in focus = editing }
		.onDisappear { editor.editing = nil }
	}

	private var selectionPanel: some View {
		Panel(title: state.modulePlacement == nil ? "Selection" : "Place module") {
			if let placement = state.modulePlacement {
				ModulePlacementInspector(placement: placement) { state.cancelSessions() }
			} else if state.selection.count == 1, let id = state.selection.moduleIDs.first {
				ModuleInspector(design: $design, id: id, layout: false, focus: $focus) {
					operations.selectModuleSource(id)
				}
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
	}
}
