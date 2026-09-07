import SwiftUI

@MainActor
struct SchematicToolBar: ToolbarContent {
	@Binding var state: SchematicState
	@Binding var sheet: Sheet?
	var shortcuts: Bool = true

	var body: some ToolbarContent {
		ToolbarItemGroup {
			ForEach(SchematicTool.allCases, id: \.self) { tool in
				ToolButton(tool: tool, state: $state.tool, shortcuts: shortcuts)
			}
		}
	}
}
