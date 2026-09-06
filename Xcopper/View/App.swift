import SwiftUI

@main
@MainActor
struct XcopperApp: App {
	@State var clipboard: Clipboard = .init()

	var body: some Scene {
		DocumentGroup(newDocument: Document()) { cfg in
			EditorView(design: cfg.$document.design, clipboard: $clipboard)
		}
		.windowToolbarStyle(.unified)
		.defaultWindowPlacement { _, context in
			let screen = context.defaultDisplay.visibleRect
			return WindowPlacement(screen.origin, size: screen.size)
		}
		.commands { MenuCommands() }
	}
}
