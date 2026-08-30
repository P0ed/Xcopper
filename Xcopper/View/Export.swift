import AppKit
import SwiftUI

extension Operations {

	/// Asks where the fabrication set should go, writes it there and shows the
	/// result in the Finder
	func exportFabrication() {
		let stem = Fabrication.stem(documentName)

		let panel = NSSavePanel()
		panel.title = "Export Gerbers"
		panel.message = "Choose where to write the Gerber and drill files"
		panel.prompt = "Export"
		panel.nameFieldLabel = "Folder:"
		panel.nameFieldStringValue = "\(stem) gerbers"
		panel.canCreateDirectories = true

		guard panel.runModal() == .OK, let directory = panel.url else { return }

		let files = design.fabrication(named: stem)
		do {
			try Fabrication.write(files, to: directory)
			NSWorkspace.shared.activateFileViewerSelecting(
				files.map { file in directory.appending(path: file.name) }
			)
		} catch {
			let alert = NSAlert()
			alert.messageText = "Could not write the fabrication set"
			alert.informativeText = error.localizedDescription
			alert.runModal()
		}
	}
}
