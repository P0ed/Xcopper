import SwiftUI

@main
@MainActor
struct XcopperApp: App {
	@State var clipboard: Clipboard = .init()

	var body: some Scene {
		DocumentGroup(newDocument: Document()) { cfg in
			EditorView(
				design: MCPDocuments.shared.observing(
					cfg.$document.design.synchronizingBoard,
					id: cfg.document.runtimeID
				),
				clipboard: $clipboard, documentID: cfg.document.runtimeID
			)
		}
		.windowToolbarStyle(.unified)
		.defaultWindowPlacement { _, context in
			let screen = context.defaultDisplay.visibleRect
			return WindowPlacement(screen.origin, size: screen.size)
		}
		.commands { MenuCommands() }

		Settings {
			TabView {
				AIAccessSettings().tabItem { Label("AI Access", systemImage: "network") }
			}
		}
	}
}
