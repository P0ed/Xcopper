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
	var wires: [Wire] = []
	var modules: [ModuleInstance] = []

	var layoutIsEmpty: Bool {
		traces.isEmpty && vias.isEmpty && holes.isEmpty && footprints.isEmpty && modules.isEmpty
	}

	var schematicIsEmpty: Bool {
		footprints.isEmpty && wires.isEmpty && modules.isEmpty
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

	var snap: µm { mode == .layout ? layout.selectionGrid : schematic.snap }

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
	var canDelete: Bool {
		if mode == .layout, let session = layout.traceSession { return !session.anchors.isEmpty }
		return hasSelection && !hasReadOnlySelection
	}
	var hasPadSelection: Bool { mode == .layout && layout.selection.containsPads }
	var hasReadOnlySelection: Bool {
		hasPadSelection || (mode == .layout && design.containsModuleParts(layout.selection))
	}
	var canAssignNet: Bool {
		mode == .layout && !layout.selection.isEmpty && !hasReadOnlySelection
			&& layout.selection.allSatisfy { $0.kind == .trace || $0.kind == .via }
	}

	var offset: Point { Point(x: Int(snap) * 4, y: Int(snap) * 4) }

	var pasteOffset: Point {
		guard mode == .layout else { return offset }
		let placement = !clipboard.footprints.isEmpty || !clipboard.holes.isEmpty || !clipboard.modules.isEmpty
		let grid = placement ? layout.placementGrid : layout.routingGrid
		return Point(x: Int(grid) * 4, y: Int(grid) * 4)
	}

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
		case .schematic: schematic.viewport.fit(design.board.sheetSize)
		case .preview: preview.frame(design.resolved.board)
		}
	}

	func delete() {
		if mode == .layout, layout.traceSession != nil {
			layout.backtrackTrace(in: &design.board)
			return
		}
		deleteSelection()
	}

	private func deleteSelection() {
		guard !hasReadOnlySelection else { return }
		switch mode {
		case .layout:
			let counterparts = design.deleteLayout(layout.selection)
			layout.resetTransientInteractions()
			if counterparts { schematic.resetTransientInteractions() }
		case .schematic:
			let counterparts = design.deleteSchematic(schematic.selection)
			schematic.resetTransientInteractions()
			if counterparts { layout.resetTransientInteractions() }
		case .preview: return
		}
	}

	func rotate(clockwise: Bool) {
		guard !hasReadOnlySelection else { return }
		switch mode {
		case .layout: design.rotateLayout(layout.selection, clockwise: clockwise)
		case .schematic: design.rotateSchematic(schematic.selection, clockwise: clockwise)
		case .preview: break
		}
	}

	func flip() {
		guard !hasModuleSelection, !hasReadOnlySelection else { return }
		switch mode {
		case .layout: design.board.flip(layout.selection)
		case .schematic: design.board.mirrorSchematic(schematic.selection)
		case .preview: break
		}
	}

	func duplicate() {
		guard !hasReadOnlySelection else { return }
		switch mode {
		case .layout: layout.selection = design.duplicateLayout(layout.selection, by: offset)
		case .schematic: schematic.selection = design.duplicateSchematic(schematic.selection, by: offset)
		case .preview: break
		}
	}

	func selectAll() {
		switch mode {
		case .layout: layout.selection = design.layoutRefs(in: design.board.bounds, layers: layout.selectionLayers(in: design.board.stack))
		case .schematic: schematic.selection = design.schematicRefs(in: design.board.sheetBounds)
		case .preview: break
		}
	}

	func nudge(dx: Int = 0, dy: Int = 0) {
		guard !hasReadOnlySelection else { return }
		let delta = Point(x: dx * Int(snap), y: dy * Int(snap))
		switch mode {
		case .layout:
			var moved = design
			guard let selection = moved.moveLayout(layout.selection, by: delta, grid: layout.routingGrid) else { return }
			design = moved
			layout.selection = selection
		case .schematic:
			if let selection = design.moveSchematic(schematic.selection, by: delta, grid: snap) {
				schematic.selection = selection
			}
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
			reveal(refs)
			editor.mode = .layout
		case .layout:
			let refs = design.symbols(for: layout.selection)
			guard !refs.isEmpty else { return }
			reveal(refs)
			editor.mode = .schematic
		case .preview:
			break
		}
	}

	func find(_ query: String) {
		switch mode {
		case .layout: reveal(design.layoutRefs(matching: query))
		case .schematic: reveal(design.schematicRefs(matching: query))
		case .preview: break
		}
	}

	func show(_ violation: Violation) {
		reveal(violation.refs, at: violation.at)
		if let layer = violation.layer { layout.layer = layer }
		editor.mode = .layout
	}

	private func reveal(_ refs: Set<Ref>, at point: Point? = nil) {
		layout.cancelSessions()
		layout.selection = refs
		if let at = point ?? design.layoutBounds(refs)?.center { layout.viewport.reveal(at) }
	}

	private func reveal(_ refs: Set<SchematicRef>) {
		schematic.cancelSessions()
		schematic.selection = refs
		if let at = design.schematicBounds(refs)?.center { schematic.viewport.reveal(at) }
	}

	func place(_ device: Device) {
		switch mode {
		case .layout:
			layout.spec = Footprint.Spec(kind: .chip, chip: .c1206, device: device)
			layout.tool = .footprint
		case .schematic:
			schematic.spec = Symbol.Spec(kind: device.symbolKind)
			schematic.tool = .symbol
		case .preview:
			break
		}
	}

	func assignNet(_ net: Net.ID?) {
		guard canAssignNet else { return }
		for ref in layout.selection {
			design.board[net: ref] = net
		}
	}
}

extension Operations {

	func cut() {
		copy()
		deleteSelection()
	}

	func copy() {
		guard !hasReadOnlySelection else { return }
		let ids = selectedModuleIDs
		var next = Clipboard()
		next.modules = design.modules.filter { ids.contains($0.id) }
		switch mode {
		case .layout:
			let refs = layout.selection.sorted(by: Ref.order)
			let board = design.board
			next.traces = refs.compactMap { if case let .trace(i) = $0, board.traces.indices.contains(i) { board.traces[i] } else { nil } }
			next.vias = refs.compactMap { if case let .via(i) = $0, board.vias.indices.contains(i) { board.vias[i] } else { nil } }
			next.holes = refs.compactMap { if case let .hole(i) = $0, board.holes.indices.contains(i) { board.holes[i] } else { nil } }
			next.footprints = design.footprints(at: refs)
		case .schematic:
			let refs = schematic.selection.sorted(by: SchematicRef.order)
			let sheet = design.board
			next.wires = refs.compactMap { if case let .wire(i) = $0, sheet.wires.indices.contains(i) { sheet.wires[i] } else { nil } }
			next.footprints = design.footprints(at: design.footprints(for: schematic.selection).sorted(by: Ref.order))
		case .preview:
			return
		}
		clipboard = next
	}

	func paste() {
		guard canPaste else { return }
		guard let moduleIDs = pasteModules() else { return }
		switch mode {
		case .layout: pasteLayout(moduleIDs: moduleIDs)
		case .schematic: pasteSchematic(moduleIDs: moduleIDs)
		case .preview: break
		}
	}

	private func pasteLayout(moduleIDs: Set<UUID>) {
		let delta = pasteOffset
		var next = design
		var created: Set<Ref> = []

		for trace in clipboard.traces where next.board.stack.contains(trace.layer) {
			next.board.traces.append(modifying(trace) { trace in
				trace.start = trace.start + delta
				trace.end = trace.end + delta
			})
			created.insert(.trace(next.board.traces.count - 1))
		}
		for via in clipboard.vias {
			next.board.vias.append(modifying(via) { via in
				via.at = via.at + delta
			})
			created.insert(.via(next.board.vias.count - 1))
		}
		for hole in clipboard.holes {
			next.board.holes.append(modifying(hole) { hole in hole.at = hole.at + delta })
			created.insert(.hole(next.board.holes.count - 1))
		}
		var taken = next.moduleProjection().sheet.schematicOccupied
		var used = next.usedReferences
		for footprint in clipboard.footprints {
			let reference = Xcopper.nextReference(like: footprint.reference, used: used)
			used.insert(reference)
			next.board.footprints.append(modifying(footprint) { copy in
				copy.at = copy.at + delta
				copy.reference = reference
				copy.symbol.at = next.board.parking(for: copy.symbol, clear: taken)
				taken.append(copy.symbol.placedExtent)
			})
			created.insert(.footprint(next.board.footprints.count - 1))
		}
		design = next
		layout.selection = created.union(moduleIDs.map(Ref.module))
	}

	private func pasteSchematic(moduleIDs: Set<UUID>) {
		let delta = offset
		var next = design
		var created: Set<SchematicRef> = []

		for wire in clipboard.wires {
			next.board.wires.append(modifying(wire) { wire in
				wire.start = wire.start + delta
				wire.end = wire.end + delta
			})
			created.insert(.wire(next.board.wires.count - 1))
		}
		var taken = next.board.occupied
		var used = next.usedReferences
		for footprint in clipboard.footprints {
			let reference = Xcopper.nextReference(like: footprint.reference, used: used)
			used.insert(reference)
			next.board.footprints.append(modifying(footprint) { copy in
				copy.symbol.at = copy.symbol.at + delta
				copy.reference = reference
				copy.at = next.board.parking(for: copy, clear: taken)
				taken.append(copy.placedExtent)
			})
			created.insert(.symbol(next.board.footprints.count - 1))
		}
		design = next
		schematic.selection = created.union(moduleIDs.map(SchematicRef.module))
	}
}

extension Operations {

	func configureBoard(sheet: Size, size: Size, stack: Stack, solderMask: Bool) {
		guard stack == design.board.stack || design.canRestack(stack) else {
			moduleAlert("Cannot reduce the layer count", "An imported module needs more layers. Remove it or change its source stack first.")
			return
		}
		design = modifying(design) { design in
			design.board.sheetSize = sheet
			design.board.size = size
			design.board.solderMask = solderMask
			if stack != design.board.stack {
				design.restack(stack)
				layout.clampLayer(design.board.stack)
			}
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
}
