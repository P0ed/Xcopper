import SwiftUI

struct Operations {
	@Binding var state: EditorState
	@Binding var board: Board
	@Binding var clipboard: Clipboard
}

struct Clipboard: Equatable, Codable {
	var traces: [Trace] = []
	var vias: [Via] = []
	var holes: [Hole] = []
	var footprints: [Footprint] = []

	var isEmpty: Bool {
		traces.isEmpty && vias.isEmpty && holes.isEmpty && footprints.isEmpty
	}
}

extension Operations {

	var hasSelection: Bool { !state.selection.isEmpty }

	func scaleToFit() {
		state.setScale(board.size.zoomToFit(state.size, margin: Layout.margin))
	}

	func delete() {
		board.remove(state.selection)
		state.resetTransientInteractions()
	}

	func rotate(clockwise: Bool) {
		board.rotate(state.selection, clockwise: clockwise)
	}

	func flip() {
		board.flip(state.selection)
	}

	func duplicate() {
		let delta = Pt(x: Int(state.grid) * 4, y: Int(state.grid) * 4)
		state.selection = board.duplicate(state.selection, by: delta)
	}

	func assignNet(_ net: Net.ID?) {
		for ref in state.selection {
			board[net: ref] = net
		}
	}

	func selectAll() {
		state.selection = board.refs(in: board.bounds, layer: state.layer)
	}

	func cut() {
		copy()
		delete()
	}

	func copy() {
		let refs = state.selection
		clipboard = Clipboard(
			traces: refs.compactMap { if case let .trace(i) = $0, board.traces.indices.contains(i) { board.traces[i] } else { nil } },
			vias: refs.compactMap { if case let .via(i) = $0, board.vias.indices.contains(i) { board.vias[i] } else { nil } },
			holes: refs.compactMap { if case let .hole(i) = $0, board.holes.indices.contains(i) { board.holes[i] } else { nil } },
			footprints: refs.compactMap { if case let .footprint(i) = $0, board.footprints.indices.contains(i) { board.footprints[i] } else { nil } }
		)
	}

	func paste() {
		guard !clipboard.isEmpty else { return }
		let delta = Pt(x: Int(state.grid) * 4, y: Int(state.grid) * 4)
		var created: Set<Ref> = []

		for trace in clipboard.traces where board.stack.contains(trace.layer) {
			board.traces.append(modifying(trace) { trace in
				trace.start = trace.start + delta
				trace.end = trace.end + delta
			})
			created.insert(.trace(board.traces.count - 1))
		}
		for via in clipboard.vias {
			board.vias.append(modifying(via) { via in
				via.at = via.at + delta
				via.from = min(via.from, board.stack.bottom)
				via.to = min(via.to, board.stack.bottom)
			})
			created.insert(.via(board.vias.count - 1))
		}
		for hole in clipboard.holes {
			board.holes.append(modifying(hole) { hole in hole.at = hole.at + delta })
			created.insert(.hole(board.holes.count - 1))
		}
		for footprint in clipboard.footprints {
			board.footprints.append(modifying(footprint) { footprint in
				footprint.at = footprint.at + delta
				footprint.reference = board.nextReference(like: footprint.reference)
			})
			created.insert(.footprint(board.footprints.count - 1))
		}
		state.selection = created
	}

	func nudge(dx: Int = 0, dy: Int = 0) {
		let step = Int(state.grid)
		board.move(state.selection, by: Pt(x: dx * step, y: dy * step))
	}
}

extension Operations {

	func resize(size: Size, stack: Stack) {
		board.resize(size: size)
		if stack != board.stack {
			board.restack(stack)
			state.clampLayer(board.stack)
		}
		state.resetTransientInteractions()
	}

	func addNet(name: String) {
		state.net = board.addNet(name: name)
	}

	func removeNet(_ id: Net.ID) {
		board.removeNet(id)
		if state.net == id { state.net = nil }
	}

	func setPlane(_ net: Net.ID?, on layer: Int) {
		board.setPlane(net, on: layer)
	}
}
