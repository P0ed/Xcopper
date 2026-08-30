import AppKit
import SwiftUI

extension LayoutView {

	func point(at location: CGPoint) -> Pt {
		Layout.point(location, scale: state.viewport.magnification)
	}

	var snapRadius: Int { max(Int(state.snap), Int(Nm.mm(0.4))) }

	var hitTolerance: Int { Int(Nm.mm(0.6) / Nm(max(1, Int(state.viewport.magnification / 4)))) }

	/// Grid position, overridden by a nearby pad, via or trace endpoint
	func snapped(_ point: Pt, layer: Int) -> (Pt, Net.ID?) {
		if !modifierFlags.contains(.control),
			let target = board.snapTarget(near: point, layer: layer, radius: snapRadius) {
			return target
		}
		return (point.snapped(to: state.snap), nil)
	}

	var editingController: some Gesture {
		DragGesture(minimumDistance: 0.0)
			.onChanged { gesture in
				let start = point(at: gesture.startLocation)
				let current = point(at: gesture.location)

				switch state.tool {
				case .select:
					dragSelection(from: start, to: current)
				case .trace:
					state.beginTrace(at: routeStart(start))
					state.updateTrace(to: routeEnd(current))
				case .via, .hole, .footprint:
					break
				}
			}
			.onEnded { gesture in
				let start = point(at: gesture.startLocation)
				let current = point(at: gesture.location)

				switch state.tool {
				case .select:
					endSelection(from: start, to: current)
				case .trace:
					state.updateTrace(to: routeEnd(current))
					if let trace = state.endTrace() {
						// A route that has reached a pad, a via or copper already
						// drawn has nowhere left to chain to, so the tool steps aside
						let landed = board.isConnection(trace.end, layer: trace.layer)
						undoGroup(Tool.trace.actionName) { board.traces.append(trace) }
						if landed { state.tool = .select }
					}
				case .via:
					undoGroup(Tool.via.actionName) { placeVia(at: current) }
				case .hole:
					undoGroup(Tool.hole.actionName) { placeHole(at: current) }
				case .footprint:
					undoGroup(Tool.footprint.actionName) { placeFootprint(at: current) }
				}
			}
	}

	func hover(at location: CGPoint) {
		let point = point(at: location)
		state.viewport.cursor = state.tool == .trace && state.traceSession != nil
			? routeEnd(point)
			: snapped(point, layer: state.layer).0
		guard state.tool == .trace else { return }
		state.hoverTrace(to: state.viewport.cursor)
	}
}

private extension LayoutView {

	var modifierFlags: NSEvent.ModifierFlags { NSEvent.modifierFlags }

	var selectionMode: SelectionMode {
		SelectionMode(
			shift: modifierFlags.contains(.shift),
			option: modifierFlags.contains(.option)
		)
	}

	/// Whether the pointer takes the whole run rather than the one segment on it
	var picksRun: Bool { modifierFlags.contains(.command) }

	func undoGroup(_ name: String, _ body: () -> Void = {}) {
		undoManager?.beginUndoGrouping()
		body()
		undoManager?.setActionName(name)
		undoManager?.endUndoGrouping()
	}

	func routeStart(_ point: Pt) -> Pt {
		let (snapped, net) = snapped(point, layer: state.layer)
		if let net, state.traceSession == nil { state.net = net }
		return snapped
	}

	/// Object snap wins, then free angle while shift is held, 45 degrees otherwise
	func routeEnd(_ point: Pt) -> Pt {
		guard let session = state.traceSession else {
			return snapped(point, layer: state.layer).0
		}
		if !modifierFlags.contains(.control),
			let (target, _) = board.snapTarget(near: point, layer: session.layer, radius: snapRadius) {
			return target
		}
		guard !modifierFlags.contains(.shift) else { return point.snapped(to: state.snap) }

		let projected = snapped45(from: session.start, to: point)
		return session.start + (projected - session.start).snapped(to: state.snap)
	}

	func dragSelection(from start: Pt, to current: Pt) {
		if state.moveSession != nil {
			return state.updateMove(to: current.snapped(to: state.snap))
		}
		if state.selectSession == nil, !picksRun {
			let hit = board.hitTest(at: start, layer: state.layer, tolerance: hitTolerance)
			if let hit, state.selection.contains(hit) {
				state.beginMove(at: start.snapped(to: state.snap))
				return state.updateMove(to: current.snapped(to: state.snap))
			}
		}
		state.beginSelect(at: start, mode: selectionMode)
		state.updateSelect(to: current)
	}

	func endSelection(from start: Pt, to current: Pt) {
		if let session = state.moveSession {
			if session.didMove {
				undoGroup("Move") { board.move(state.selection, by: session.delta) }
			}
			state.moveSession = nil
			return
		}
		guard let session = state.selectSession else { return }
		state.updateSelect(to: current)

		let whole = picksRun
		let hit: Set<Ref> = session.didDrag
			? board.refs(in: session.rect, layer: state.layer, whole: whole)
			: board.refs(at: start, layer: state.layer, tolerance: hitTolerance, whole: whole)

		state.selection = session.mode.apply(session.initial, hit)
		state.selectSession = nil
	}

	func placeVia(at point: Pt) {
		let (at, net) = snapped(point, layer: state.layer)
		board.vias.append(Via(
			at: at,
			drill: board.rules.viaDrill,
			pad: board.rules.viaPad,
			from: board.stack.top,
			to: board.stack.bottom,
			net: net ?? state.net
		))
	}

	func placeHole(at point: Pt) {
		board.holes.append(Hole(
			at: point.snapped(to: state.snap),
			diameter: .mm(3.2)
		))
	}

	func placeFootprint(at point: Pt) {
		let footprint = Footprint(
			spec: state.spec,
			reference: board.nextReference(like: state.spec.referencePrefix),
			at: point.snapped(to: state.snap)
		)
		board.footprints.append(footprint)
		state.selection = [.footprint(board.footprints.count - 1)]
	}
}
