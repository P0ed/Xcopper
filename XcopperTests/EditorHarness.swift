import SwiftUI
import XCTest
@testable import Xcopper

@MainActor
final class EditorHarness {
	var design: Design
	var editor = EditorState()
	var layout = LayoutState()
	var schematic = SchematicState()
	var preview = PreviewState()
	var clipboard = Clipboard()
	var url: URL?
	let undo = UndoManager()
	init(design: Design) { self.design = design; undo.groupsByEvent = false }
	func replace(_ next: Design) {
		let previous = design
		guard next != previous else { return }
		undo.registerUndo(withTarget: self) { $0.replace(previous) }
		design = next
	}
	func binding<T>(_ path: ReferenceWritableKeyPath<EditorHarness, T>) -> Binding<T> {
		Binding(get: { self[keyPath: path] }, set: { self[keyPath: path] = $0 })
	}
	var operations: Operations {
		Operations(editor: binding(\.editor), layout: binding(\.layout), schematic: binding(\.schematic), preview: binding(\.preview),
			design: Binding(get: { self.design }, set: { self.replace($0) }), clipboard: binding(\.clipboard), documentURL: url, documentName: "Parent")
	}
	func perform(_ action: (Operations) -> Void) {
		undo.beginUndoGrouping()
		action(operations)
		undo.endUndoGrouping()
	}
}
