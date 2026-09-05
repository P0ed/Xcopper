import SwiftUI
import UniformTypeIdentifiers

extension UTType {
	static var xcb: Self { UTType("p0.xcopper.xcb")! }
}

struct Document: FileDocument {
	var design: Design

	static var readableContentTypes: [UTType] { [.xcb] }

	init(design: Design = Design()) {
		self.design = design
	}

	init(configuration: ReadConfiguration) throws {
		design = try Document.decode(
			configuration.file.regularFileContents.throwing("Failed to read file")
		)
	}

	static func decode(_ data: Data) throws -> Design {
		let design = try JSONDecoder().decode(Design.self, from: data)

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
