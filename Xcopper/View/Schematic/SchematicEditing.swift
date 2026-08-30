import AppKit
import SwiftUI

extension SchematicView {

	func point(at location: CGPoint) -> Pt {
		Layout.point(location, scale: state.viewport.magnification)
	}

	var snapRadius: Int { max(Int(state.grid), Int(Nm.mm(0.8))) }

	var hitTolerance: Int { Int(Nm.mm(1.2) / Nm(max(1, Int(state.viewport.magnification / 4)))) }

	/// Grid position, overridden by a nearby pin tip or wire end
	func snapped(_ point: Pt) -> Pt {
		if !modifierFlags.contains(.control),
			let target = schematic.snapTarget(near: point, radius: snapRadius) {
			return target
		}
		return point.snapped(to: state.grid)
	}

	var editingController: some Gesture {
		DragGesture(minimumDistance: 0.0)
			.onChanged { gesture in
				let start = point(at: gesture.startLocation)
				let current = point(at: gesture.location)

				switch state.tool {
				case .select:
					dragSelection(from: start, to: current)
				case .wire:
					state.beginWire(at: snapped(start))
					state.updateWire(to: wireEnd(current))
				case .label, .symbol:
					break
				}
			}
			.onEnded { gesture in
				let start = point(at: gesture.startLocation)
				let current = point(at: gesture.location)

				switch state.tool {
				case .select:
					endSelection(from: start, to: current)
				case .wire:
					state.updateWire(to: wireEnd(current))
					if let wire = state.endWire() {
						undoGroup(SchematicTool.wire.actionName) { schematic.wires.append(wire) }
					}
				case .label:
					undoGroup(SchematicTool.label.actionName) { placeLabel(at: current) }
				case .symbol:
					undoGroup(SchematicTool.symbol.actionName) { placeSymbol(at: current) }
				}
			}
	}

	func hover(at location: CGPoint) {
		let point = point(at: location)
		state.viewport.cursor = state.tool == .wire && state.wireSession != nil
			? wireEnd(point)
			: snapped(point)
		guard state.tool == .wire else { return }
		state.hoverWire(to: state.viewport.cursor)
	}
}

private extension SchematicView {

	var modifierFlags: NSEvent.ModifierFlags { NSEvent.modifierFlags }

	var selectionMode: SelectionMode {
		SelectionMode(
			shift: modifierFlags.contains(.shift),
			option: modifierFlags.contains(.option)
		)
	}

	func undoGroup(_ name: String, _ body: () -> Void = {}) {
		undoManager?.beginUndoGrouping()
		body()
		undoManager?.setActionName(name)
		undoManager?.endUndoGrouping()
	}

	/// Object snap wins, then a free angle while shift is held, orthogonal otherwise
	func wireEnd(_ point: Pt) -> Pt {
		guard let session = state.wireSession else { return snapped(point) }

		if !modifierFlags.contains(.control),
			let target = schematic.snapTarget(near: point, radius: snapRadius) {
			return target
		}
		guard !modifierFlags.contains(.shift) else { return point.snapped(to: state.grid) }

		let projected = snapped90(from: session.start, to: point)
		return session.start + (projected - session.start).snapped(to: state.grid)
	}

	func dragSelection(from start: Pt, to current: Pt) {
		if state.moveSession != nil {
			return state.updateMove(to: current.snapped(to: state.grid))
		}
		if state.selectSession == nil {
			let hit = schematic.hitTest(at: start, tolerance: hitTolerance)
			if let hit, state.selection.contains(hit) {
				state.beginMove(at: start.snapped(to: state.grid))
				return state.updateMove(to: current.snapped(to: state.grid))
			}
		}
		state.beginSelect(at: start, mode: selectionMode)
		state.updateSelect(to: current)
	}

	func endSelection(from start: Pt, to current: Pt) {
		if let session = state.moveSession {
			if session.didMove {
				undoGroup("Move") { schematic.move(state.selection, by: session.delta) }
			}
			state.moveSession = nil
			return
		}
		guard let session = state.selectSession else { return }
		state.updateSelect(to: current)

		let hit: Set<Schematic.Ref> = session.didDrag
			? schematic.refs(in: session.rect)
			: schematic.hitTest(at: start, tolerance: hitTolerance).map { [$0] } ?? []

		state.selection = session.mode.apply(session.initial, hit)
		state.selectSession = nil
	}

	func placeLabel(at point: Pt) {
		let text = state.label.trimmingWhitespace
		guard !text.isEmpty else { return }
		schematic.labels.append(NetLabel(at: snapped(point), text: text))
		state.selection = [.label(schematic.labels.count - 1)]
	}

	func placeSymbol(at point: Pt) {
		let symbol = Symbol(
			spec: state.spec,
			reference: schematic.nextReference(like: state.spec.referencePrefix),
			at: point.snapped(to: state.grid)
		)
		schematic.symbols.append(symbol)
		state.selection = [.symbol(schematic.symbols.count - 1)]
	}
}
