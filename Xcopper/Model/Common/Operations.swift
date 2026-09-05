import SwiftUI

@MainActor
struct Operations {
	@Binding var editor: EditorState
	@Binding var layout: LayoutState
	@Binding var schematic: SchematicState
	@Binding var preview: PreviewState
	@Binding var design: Design
	@Binding var clipboard: Clipboard

	var documentURL: URL? = nil
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
	var modules: [ModuleInstance] = []

	var layoutIsEmpty: Bool {
		traces.isEmpty && vias.isEmpty && holes.isEmpty && footprints.isEmpty && modules.isEmpty
	}

	var schematicIsEmpty: Bool {
		symbols.isEmpty && wires.isEmpty && labels.isEmpty && modules.isEmpty
	}

	func isEmpty(in mode: Mode) -> Bool {
		switch mode {
		case .layout: layoutIsEmpty
		case .schematic: schematicIsEmpty
		case .preview: true
		}
	}
}

extension Operations {

	var mode: Mode { editor.mode }

	var snap: Nm { mode == .layout ? layout.snap : schematic.snap }

	var magnification: CGFloat {
		switch mode {
		case .layout: layout.viewport.magnification
		case .schematic: schematic.viewport.magnification
		case .preview: preview.magnification
		}
	}

	var hasSelection: Bool {
		switch mode {
		case .layout: !layout.selection.isEmpty
		case .schematic: !schematic.selection.isEmpty
		case .preview: false
		}
	}

	var canPaste: Bool { !clipboard.isEmpty(in: mode) }

	private var offset: Pt { Pt(x: Int(snap) * 4, y: Int(snap) * 4) }

	func setScale(_ scale: CGFloat) {
		switch mode {
		case .layout: layout.viewport.setScale(scale)
		case .schematic: schematic.viewport.setScale(scale)
		case .preview: preview.magnification = scale
		}
	}

	func scaleToFit() {
		switch mode {
		case .layout: layout.viewport.fit(design.board.size)
		case .schematic: schematic.viewport.fit(design.schematic.size)
		case .preview: preview.frame(design.resolved.board)
		}
	}

	func delete() {
		let ids = selectedModuleIDs
		switch mode {
		case .layout:
			design.removeModules(layout.selection.moduleIDs)
			design.board.remove(layout.selection)
			layout.resetTransientInteractions()
		case .schematic:
			design.removeModules(schematic.selection.moduleIDs)
			design.schematic.remove(schematic.selection)
			schematic.resetTransientInteractions()
		case .preview:
			break
		}
		layout.selection.subtract(ids.map(Ref.module))
		schematic.selection.subtract(ids.map(Schematic.Ref.module))
	}

	func rotate(clockwise: Bool) {
		switch mode {
		case .layout: design.rotateLayout(layout.selection, clockwise: clockwise)
		case .schematic: design.rotateSchematic(schematic.selection, clockwise: clockwise)
		case .preview: break
		}
	}

	func flip() {
		guard !hasModuleSelection else { return }
		switch mode {
		case .layout: design.board.flip(layout.selection)
		case .schematic: design.schematic.mirror(schematic.selection)
		case .preview: break
		}
	}

	func duplicate() {
		let ids = design.duplicateModules(selectedModuleIDs, by: offset)
		switch mode {
		case .layout:
			layout.selection = design.board.duplicate(
				layout.selection,
				by: offset,
				references: Set(design.schematic.symbols.map(\.reference))
			)
		case .schematic:
			schematic.selection = design.schematic.duplicate(
				schematic.selection,
				by: offset,
				references: Set(design.board.footprints.map(\.reference))
			)
		case .preview: break
		}
		if mode == .layout { layout.selection.formUnion(ids.map(Ref.module)) }
		if mode == .schematic { schematic.selection.formUnion(ids.map(Schematic.Ref.module)) }
	}

	func selectAll() {
		switch mode {
		case .layout: layout.selection = design.layoutRefs(in: design.board.bounds, layer: layout.layer)
		case .schematic: schematic.selection = design.schematicRefs(in: design.schematic.bounds)
		case .preview: break
		}
	}

	func nudge(dx: Int = 0, dy: Int = 0) {
		let delta = Pt(x: dx * Int(snap), y: dy * Int(snap))
		switch mode {
		case .layout:
			var moved = design
			guard let selection = moved.moveLayout(layout.selection, by: delta, grid: snap) else { return }
			design = moved
			layout.selection = selection
		case .schematic: design.moveSchematic(schematic.selection, by: delta)
		case .preview: break
		}
	}

	var counterpartCount: Int {
		switch mode {
		case .schematic: design.footprints(for: schematic.selection).count
		case .layout: design.symbols(for: layout.selection).count
		case .preview: 0
		}
	}

	var counterpartName: String {
		if hasModuleSelection { return mode == .layout ? "Show schematic" : "Show layout" }
		let several = counterpartCount > 1
		return switch mode {
		case .layout: several ? "Show symbols" : "Show symbol"
		case .schematic, .preview: several ? "Show footprints" : "Show footprint"
		}
	}

	var counterpartImage: String {
		mode == .layout ? "square.on.circle" : "square.grid.3x3.square"
	}

	func showCounterpart() {
		switch mode {
		case .schematic:
			let refs = design.footprints(for: schematic.selection)
			guard !refs.isEmpty else { return }
			layout.cancelSessions()
			layout.selection = refs
			if let at = design.layoutBounds(refs)?.center { layout.viewport.reveal(at) }
			editor.mode = .layout
		case .layout:
			let refs = design.symbols(for: layout.selection)
			guard !refs.isEmpty else { return }
			schematic.cancelSessions()
			schematic.selection = refs
			if let at = design.schematicBounds(refs)?.center { schematic.viewport.reveal(at) }
			editor.mode = .schematic
		case .preview:
			break
		}
	}

	func show(_ violation: Violation) {
		layout.cancelSessions()
		layout.selection = violation.refs
		if let layer = violation.layer { layout.layer = layer }
		layout.viewport.reveal(violation.at)
		editor.mode = .layout
	}

	func place(_ part: Footprint.Part) {
		switch mode {
		case .layout:
			layout.spec = Footprint.Spec(kind: .chip, chip: .c1206, part: part)
			layout.tool = .footprint
		case .schematic:
			schematic.spec = Symbol.Spec(kind: part.symbol)
			schematic.tool = .symbol
		case .preview:
			break
		}
	}

	func assignNet(_ net: Net.ID?) {
		guard mode == .layout, !hasModuleSelection else { return }
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
		next.modules = design.modules.filter { selectedModuleIDs.contains($0.id) }
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
		case .preview:
			return
		}
		clipboard = next
	}

	func paste() {
		guard canPaste, pasteModules() else { return }
		switch mode {
		case .layout: pasteLayout()
		case .schematic: pasteSchematic()
		case .preview: break
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
				footprint.reference = design.nextReference(like: footprint.reference)
			})
			created.insert(.footprint(design.board.footprints.count - 1))
		}
		layout.selection = created.union(pastedModuleIDs.map(Ref.module))
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
				symbol.reference = design.nextReference(like: symbol.reference)
			})
			created.insert(.symbol(design.schematic.symbols.count - 1))
		}
		schematic.selection = created.union(pastedModuleIDs.map(Schematic.Ref.module))
	}
}

extension Operations {

	func resize(size: Size, stack: Stack) {
		guard design.canRestack(stack) else {
			moduleAlert("Cannot reduce the layer count", "An imported module needs more layers. Remove it or change its source stack first.")
			return
		}
		design.board.resize(size: size)
		if stack != design.board.stack {
			design.restack(stack)
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

	func updateBoard() {
		editor.report = design.updateBoardFromSchematic()
	}
}
