import SwiftUI
import UniformTypeIdentifiers

extension UTType {
	static var pcb: Self { UTType("p0.xcopper.pcb")! }
}

/// Net table of a document written before the schematic existed, when `Board`
/// was the root and owned the nets
private struct LegacyNets: Decodable {
	var nets: [Net]
}

struct Document: FileDocument {
	var design: Design

	static var readableContentTypes: [UTType] { [.pcb] }

	init(design: Design = Design()) {
		self.design = design
	}

	init(configuration: ReadConfiguration) throws {
		design = try Document.decode(
			configuration.file.regularFileContents.throwing("Failed to read file")
		)
	}

	/// Reads the current root, falling back to a document written before the
	/// schematic existed, when `Board` was the root and owned the nets.
	static func decode(_ data: Data) throws -> Design {
		let design: Design

		if let current = try? JSONDecoder().decode(Design.self, from: data) {
			design = current
		} else {
			let board = try JSONDecoder().decode(Board.self, from: data)
			let legacy = try? JSONDecoder().decode(LegacyNets.self, from: data)
			design = Design(nets: legacy?.nets ?? [], board: board, schematic: Schematic())
		}

		guard !design.board.size.isEmpty else { throw Err("Board has no size") }
		guard !design.schematic.size.isEmpty else { throw Err("Sheet has no size") }
		guard design.board.planes.count == design.board.stack.count else {
			throw Err("Corrupted layer stack")
		}
		return design
	}

	func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		return FileWrapper(regularFileWithContents: try encoder.encode(design))
	}
}
