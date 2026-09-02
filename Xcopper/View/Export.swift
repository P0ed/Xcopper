import AppKit
import SwiftUI

extension Operations {

	func exportFabrication() {
		guard preflight() else { return }
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

	private func preflight() -> Bool {
		let violations = design.check()
		guard let first = violations.first else { return true }

		let listed = violations.prefix(6).map(\.text)
		let alert = NSAlert()
		alert.alertStyle = .warning
		alert.messageText = violations.count == 1
			? "The board breaks one design rule"
			: "The board breaks \(violations.count) design rules"
		alert.informativeText = (
			listed + (violations.count > listed.count
				? ["and \(violations.count - listed.count) more"]
				: [])
		)
		.joined(separator: "\n")
		alert.addButton(withTitle: "Export Anyway")
		alert.addButton(withTitle: "Show Problem")

		guard alert.runModal() == .alertFirstButtonReturn else {
			show(first)
			return false
		}
		return true
	}
}
