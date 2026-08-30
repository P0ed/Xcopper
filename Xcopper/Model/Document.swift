import SwiftUI
import UniformTypeIdentifiers

extension UTType {
	static var pcb: Self { UTType("p0.xcopper.pcb")! }
}

struct Document: FileDocument {
	var board: Board

	static var readableContentTypes: [UTType] { [.pcb] }

	init(board: Board = Board()) {
		self.board = board
	}

	init(configuration: ReadConfiguration) throws {
		let data = try configuration.file.regularFileContents
			.throwing("Failed to read file")

		board = try JSONDecoder().decode(Board.self, from: data)

		guard !board.size.isEmpty else { throw Err("Board has no size") }
		guard board.planes.count == board.stack.count else { throw Err("Corrupted layer stack") }
	}

	func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		return FileWrapper(regularFileWithContents: try encoder.encode(board))
	}
}
