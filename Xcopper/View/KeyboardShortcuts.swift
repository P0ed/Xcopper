import SwiftUI

extension EditorView {

	var keyboardController: (KeyPress) -> KeyPress.Result {
		{ keys in
			let modifiers = keys.modifiers

			if keys.key == .escape {
				guard cancelSessions() else { return .ignored }
				return .handled
			}

			@MainActor func nudge(dx: Int = 0, dy: Int = 0) {
				guard operations.hasSelection else { return }
				DispatchQueue.main.async { operations.nudge(dx: dx, dy: dy) }
			}

			switch keys.key.character {
			case KeyEquivalent.leftArrow.character: nudge(dx: -1)
			case KeyEquivalent.rightArrow.character: nudge(dx: 1)
			case KeyEquivalent.upArrow.character: nudge(dy: -1)
			case KeyEquivalent.downArrow.character: nudge(dy: 1)
			case "g": cycleSnap(back: modifiers.contains(.shift))
			case "\u{9}" where editor.mode == .layout: layout.nextLayer(design.board.stack)
			case "\u{19}" where editor.mode == .layout: layout.prevLayer(design.board.stack)
			case "w" where editor.mode == .layout:
				cycle(&layout.traceWidth, Nm.widths, back: modifiers.contains(.shift))
			default: return .ignored
			}
			return .handled
		}
	}

	/// Whether there was anything to cancel
	private func cancelSessions() -> Bool {
		switch editor.mode {
		case .layout:
			guard layout.traceSession != nil || layout.selectSession != nil else { return false }
			layout.cancelSessions()
		case .schematic:
			guard schematic.wireSession != nil || schematic.selectSession != nil else { return false }
			schematic.cancelSessions()
		}
		return true
	}

	private func cycleSnap(back: Bool) {
		switch editor.mode {
		case .layout: cycle(&layout.snap, Nm.snapGrids, back: back)
		case .schematic: cycle(&schematic.snap, Nm.sheetSnapGrids, back: back)
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
