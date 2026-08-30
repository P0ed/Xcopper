import SwiftUI

@MainActor
struct Operations {
	@Binding var editor: EditorState
	@Binding var layout: LayoutState
	@Binding var schematic: SchematicState
	@Binding var design: Design
	@Binding var clipboard: Clipboard

	/// Name of the file on disk, the stem the fabrication set is named after
	var documentName: String
}

struct Clipboard: Equatable, Codable {
	var traces: [Trace] = []
	var vias: [Via] = []
	var holes: [Hole] = []
	var footprints: [Footprint] = []
	var symbols: [Symbol] = []
	var wires: [Wire] = []
	var labels: [NetLabel] = []

	var layoutIsEmpty: Bool {
		traces.isEmpty && vias.isEmpty && holes.isEmpty && footprints.isEmpty
	}

	var schematicIsEmpty: Bool {
		symbols.isEmpty && wires.isEmpty && labels.isEmpty
	}

	func isEmpty(in mode: Mode) -> Bool {
		mode == .layout ? layoutIsEmpty : schematicIsEmpty
	}
}

extension Operations {

	var mode: Mode { editor.mode }

	var snap: Nm { mode == .layout ? layout.snap : schematic.snap }

	var magnification: CGFloat {
		mode == .layout ? layout.viewport.magnification : schematic.viewport.magnification
	}

	var hasSelection: Bool {
		mode == .layout ? !layout.selection.isEmpty : !schematic.selection.isEmpty
	}

	var canPaste: Bool { !clipboard.isEmpty(in: mode) }

	private var offset: Pt { Pt(x: Int(snap) * 4, y: Int(snap) * 4) }

	func setScale(_ scale: CGFloat) {
		switch mode {
		case .layout: layout.viewport.setScale(scale)
		case .schematic: schematic.viewport.setScale(scale)
		}
	}

	func scaleToFit() {
		switch mode {
		case .layout: layout.viewport.fit(design.board.size)
		case .schematic: schematic.viewport.fit(design.schematic.size)
		}
	}

	func delete() {
		switch mode {
		case .layout:
			design.board.remove(layout.selection)
			layout.resetTransientInteractions()
		case .schematic:
			design.schematic.remove(schematic.selection)
			schematic.resetTransientInteractions()
		}
	}

	func rotate(clockwise: Bool) {
		switch mode {
		case .layout: design.board.rotate(layout.selection, clockwise: clockwise)
		case .schematic: design.schematic.rotate(schematic.selection, clockwise: clockwise)
		}
	}

	func flip() {
		switch mode {
		case .layout: design.board.flip(layout.selection)
		case .schematic: design.schematic.mirror(schematic.selection)
		}
	}

	func duplicate() {
		switch mode {
		case .layout: layout.selection = design.board.duplicate(layout.selection, by: offset)
		case .schematic: schematic.selection = design.schematic.duplicate(schematic.selection, by: offset)
		}
	}

	func selectAll() {
		switch mode {
		case .layout: layout.selection = design.board.refs(in: design.board.bounds, layer: layout.layer)
		case .schematic: schematic.selection = design.schematic.refs(in: design.schematic.bounds)
		}
	}

	func nudge(dx: Int = 0, dy: Int = 0) {
		let delta = Pt(x: dx * Int(snap), y: dy * Int(snap))
		switch mode {
		case .layout: design.board.move(layout.selection, by: delta)
		case .schematic: design.schematic.move(schematic.selection, by: delta)
		}
	}

	func assignNet(_ net: Net.ID?) {
		guard mode == .layout else { return }
		for ref in layout.selection {
			design.board[net: ref] = net
		}
	}
}

extension Operations {

	func cut() {
		copy()
		delete()
	}

	func copy() {
		var next = Clipboard()
		switch mode {
		case .layout:
			let refs = layout.selection
			let board = design.board
			next.traces = refs.compactMap { if case let .trace(i) = $0, board.traces.indices.contains(i) { board.traces[i] } else { nil } }
			next.vias = refs.compactMap { if case let .via(i) = $0, board.vias.indices.contains(i) { board.vias[i] } else { nil } }
			next.holes = refs.compactMap { if case let .hole(i) = $0, board.holes.indices.contains(i) { board.holes[i] } else { nil } }
			next.footprints = refs.compactMap { if case let .footprint(i) = $0, board.footprints.indices.contains(i) { board.footprints[i] } else { nil } }
		case .schematic:
			let refs = schematic.selection
			let sheet = design.schematic
			next.symbols = refs.compactMap { if case let .symbol(i) = $0, sheet.symbols.indices.contains(i) { sheet.symbols[i] } else { nil } }
			next.wires = refs.compactMap { if case let .wire(i) = $0, sheet.wires.indices.contains(i) { sheet.wires[i] } else { nil } }
			next.labels = refs.compactMap { if case let .label(i) = $0, sheet.labels.indices.contains(i) { sheet.labels[i] } else { nil } }
		}
		clipboard = next
	}

	func paste() {
		guard canPaste else { return }
		switch mode {
		case .layout: pasteLayout()
		case .schematic: pasteSchematic()
		}
	}

	private func pasteLayout() {
		let delta = offset
		var created: Set<Ref> = []

		for trace in clipboard.traces where design.board.stack.contains(trace.layer) {
			design.board.traces.append(modifying(trace) { trace in
				trace.start = trace.start + delta
				trace.end = trace.end + delta
			})
			created.insert(.trace(design.board.traces.count - 1))
		}
		for via in clipboard.vias {
			design.board.vias.append(modifying(via) { via in
				via.at = via.at + delta
				via.from = min(via.from, design.board.stack.bottom)
				via.to = min(via.to, design.board.stack.bottom)
			})
			created.insert(.via(design.board.vias.count - 1))
		}
		for hole in clipboard.holes {
			design.board.holes.append(modifying(hole) { hole in hole.at = hole.at + delta })
			created.insert(.hole(design.board.holes.count - 1))
		}
		for footprint in clipboard.footprints {
			design.board.footprints.append(modifying(footprint) { footprint in
				footprint.at = footprint.at + delta
				footprint.reference = design.board.nextReference(like: footprint.reference)
			})
			created.insert(.footprint(design.board.footprints.count - 1))
		}
		layout.selection = created
	}

	private func pasteSchematic() {
		let delta = offset
		var created: Set<Schematic.Ref> = []

		for wire in clipboard.wires {
			design.schematic.wires.append(modifying(wire) { wire in
				wire.start = wire.start + delta
				wire.end = wire.end + delta
			})
			created.insert(.wire(design.schematic.wires.count - 1))
		}
		for label in clipboard.labels {
			design.schematic.labels.append(modifying(label) { label in label.at = label.at + delta })
			created.insert(.label(design.schematic.labels.count - 1))
		}
		for symbol in clipboard.symbols {
			design.schematic.symbols.append(modifying(symbol) { symbol in
				symbol.at = symbol.at + delta
				symbol.reference = design.schematic.nextReference(like: symbol.reference)
			})
			created.insert(.symbol(design.schematic.symbols.count - 1))
		}
		schematic.selection = created
	}
}

extension Operations {

	func resize(size: Size, stack: Stack) {
		design.board.resize(size: size)
		if stack != design.board.stack {
			design.board.restack(stack)
			layout.clampLayer(design.board.stack)
		}
		layout.resetTransientInteractions()
	}

	func addNet(name: String) {
		layout.net = design.addNet(name: name)
	}

	func removeNet(_ id: Net.ID) {
		design.removeNet(id)
		if layout.net == id { layout.net = nil }
	}

	func setPlane(_ net: Net.ID?, on layer: Int) {
		design.board.setPlane(net, on: layer)
	}

	/// Pushes the schematic netlist onto the layout and keeps the result around
	/// so the sidebar can show what matched and what did not
	func updateBoard() {
		editor.report = design.updateBoardFromSchematic()
	}
}
