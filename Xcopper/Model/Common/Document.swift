import SwiftUI
import UniformTypeIdentifiers

extension UTType {
	static var xcm: Self { UTType("p0.xcopper.xcm")! }
	static var xcb: Self { UTType("p0.xcopper.xcb")! }
}

struct Document: FileDocument {
	var design: Design

	static var readableContentTypes: [UTType] { [.xcb, .xcm] }

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
		guard Set(design.modules.map(\.id)).count == design.modules.count else { throw Err("Duplicate module identities") }
		guard Set(design.modules.map(\.reference)).count == design.modules.count,
			!design.modules.contains(where: { module in
				module.reference.trimmingWhitespace.isEmpty || design.board.footprints.contains { $0.reference == module.reference }
					|| design.schematic.symbols.contains { $0.reference == module.reference }
			}) else { throw Err("Module references must be nonempty and unique") }
		return design
	}

	func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
		FileWrapper(regularFileWithContents: try encoded())
	}

	func encoded() throws -> Data {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		return try encoder.encode(design)
	}
}
