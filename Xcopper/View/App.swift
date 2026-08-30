import SwiftUI

@main
@MainActor
struct XcopperApp: App {
	@State var clipboard: Clipboard = .init()

	var body: some Scene {
		DocumentGroup(newDocument: Document()) { cfg in
			EditorView(board: cfg.$document.board, clipboard: $clipboard)
		}
		.windowToolbarStyle(.unified)
		.commands { MenuCommands() }
	}
}
