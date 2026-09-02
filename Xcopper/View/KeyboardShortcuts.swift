import SwiftUI

extension EditorView {

	var keyboardController: (KeyPress) -> KeyPress.Result {
		{ keys in
			let modifiers = keys.modifiers

			if keys.key == .escape {
				guard cancelSessions() else { return .ignored }
				return .handled
			}

			@MainActor
			func step(dx: Int = 0, dy: Int = 0) {
				if editor.mode == .preview {
					preview.camera.orbit(
						by: CGSize(width: Double(dx) * 12.0, height: Double(dy) * 12.0)
					)
				} else if operations.hasSelection {
					Task { operations.nudge(dx: dx, dy: dy) }
				}
			}

			switch keys.key.character {
			case KeyEquivalent.leftArrow.character: step(dx: -1)
			case KeyEquivalent.rightArrow.character: step(dx: 1)
			case KeyEquivalent.upArrow.character: step(dy: -1)
			case KeyEquivalent.downArrow.character: step(dy: 1)
			case "g": cycleSnap(back: modifiers.contains(.shift))
			case "\u{9}" where editor.mode == .layout: layout.nextLayer(design.board.stack)
			case "\u{19}" where editor.mode == .layout: layout.prevLayer(design.board.stack)
			default: return .ignored
			}
			return .handled
		}
	}

	private func cancelSessions() -> Bool {
		switch editor.mode {
		case .layout:
			guard layout.traceSession != nil || layout.selectSession != nil else { return false }
			layout.cancelSessions()
		case .schematic:
			guard schematic.wireSession != nil || schematic.selectSession != nil else { return false }
			schematic.cancelSessions()
		case .preview:
			return false
		}
		return true
	}

	private func cycleSnap(back: Bool) {
		switch editor.mode {
		case .layout: cycle(&layout.snap, Nm.snapGrids, back: back)
		case .schematic: cycle(&schematic.snap, Nm.sheetSnapGrids, back: back)
		case .preview: break
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
