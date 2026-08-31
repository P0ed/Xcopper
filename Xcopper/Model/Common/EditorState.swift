/// Which half of the document is on screen
enum Mode: Hashable, CaseIterable {
	case schematic, layout, preview

	var name: String {
		switch self {
		case .layout: "Layout"
		case .schematic: "Schematic"
		case .preview: "3D"
		}
	}

	var systemImage: String {
		switch self {
		case .layout: "square.stack.3d.up"
		case .schematic: "point.topleft.down.to.point.bottomright.curvepath"
		case .preview: "cube.transparent"
		}
	}

	var shortcutCharacter: Character {
		switch self {
		case .schematic: "1"
		case .layout: "2"
		case .preview: "3"
		}
	}
}

enum Sheet: String, Identifiable {
	case board, footprint, net, symbol, label

	var id: String { rawValue }
}

/// A tool the canvas can be in, in either mode
protocol ToolKind: Hashable, CaseIterable {
	var actionName: String { get }
	var systemImage: String { get }
	var shortcutCharacter: Character { get }
}

struct EditorState: Equatable {
	var mode: Mode = .schematic
	var sheet: Sheet?
	var report: Design.Report?
	/// An inspector field has the keyboard, so what is typed belongs to it
	var editing: Bool = false
}

extension EditorState {
	var dialogPresented: Bool { sheet != nil }

	/// Whether a plain key press is the canvas's to act on. A dialog or an
	/// inspector field wants the same letters the tools are picked with, and
	/// the same backspace the selection is deleted with.
	var keysAvailable: Bool { sheet == nil && !editing }
}
