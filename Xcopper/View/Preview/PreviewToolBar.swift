import SwiftUI

@MainActor
struct PreviewToolBar: ToolbarContent {
	var board: Board
	@Binding var state: PreviewState

	var body: some ToolbarContent {
		ToolbarItemGroup {
			StandButton(stand: .top, shortcut: "T", board: board, state: $state)
			StandButton(stand: .bottom, shortcut: "B", board: board, state: $state)
			StandButton(stand: .front, shortcut: "F", board: board, state: $state)
			StandButton(stand: .angled, shortcut: "A", board: board, state: $state)
		}
		ToolbarItemGroup { Spacer() }
		ToolbarItemGroup {
			ActionButton(
				name: "Fit",
				image: "arrow.up.left.and.down.right.magnifyingglass",
				action: { state.frame(board) }
			)
		}
	}
}

@MainActor
struct StandButton: View {
	var stand: Standpoint
	var shortcut: Character
	var board: Board
	@Binding var state: PreviewState

	private var isActive: Bool {
		abs(state.camera.elevation - stand.elevation) < 0.001
			&& abs(state.camera.azimuth - stand.azimuth) < 0.001
	}

	var body: some View {
		Button(stand.name, systemImage: stand.systemImage) { state.look(from: stand, at: board) }
			.foregroundStyle(isActive ? Color.accentColor : .primary)
			.keyboardShortcut(KeyEquivalent(shortcut), modifiers: [])
	}
}
