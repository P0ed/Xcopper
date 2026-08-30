import SwiftUI

extension EditorView {

	var keyboardController: (KeyPress) -> KeyPress.Result {
		{ keys in
			let modifiers = keys.modifiers

			if keys.key == .escape {
				guard state.traceSession != nil || state.selectSession != nil else {
					return .ignored
				}
				state.cancelSessions()
				return .handled
			}

			@MainActor func nudge(dx: Int = 0, dy: Int = 0) {
				guard !state.selection.isEmpty else { return }
				DispatchQueue.main.async { operations.nudge(dx: dx, dy: dy) }
			}

			switch keys.key.character {
			case "\u{9}": state.nextLayer(board.stack)
			case "\u{19}": state.prevLayer(board.stack)
			case KeyEquivalent.leftArrow.character: nudge(dx: -1)
			case KeyEquivalent.rightArrow.character: nudge(dx: 1)
			case KeyEquivalent.upArrow.character: nudge(dy: -1)
			case KeyEquivalent.downArrow.character: nudge(dy: 1)
			case "g": cycle(&state.grid, Nm.grids, back: modifiers.contains(.shift))
			case "w": cycle(&state.traceWidth, Nm.widths, back: modifiers.contains(.shift))
			default: return .ignored
			}
			return .handled
		}
	}

	private func cycle(_ value: inout Nm, _ options: [Nm], back: Bool) {
		guard let index = options.firstIndex(of: value) else {
			value = options[0]
			return
		}
		let step = back ? options.count - 1 : 1
		value = options[(index + step) % options.count]
	}
}
