import SwiftUI

@MainActor
struct SchematicToolBar: ToolbarContent {
	@Binding var state: SchematicState
	@Binding var sheet: Sheet?
	var update: () -> Void

	var body: some ToolbarContent {
		ToolbarItemGroup {
			ForEach(SchematicTool.allCases, id: \.self) { tool in
				ToolButton(tool: tool, state: $state.tool)
			}
		}
		ToolbarItemGroup { Spacer() }
		ToolbarItemGroup {
			ActionButton(
				name: "Symbol",
				image: "square.on.circle",
				action: { sheet = .symbol }
			)
			ActionButton(
				name: "Label",
				image: "tag",
				action: { sheet = .label }
			)
			ActionButton(
				name: "Update board",
				image: "arrow.triangle.2.circlepath",
				action: update
			)
		}
	}
}
