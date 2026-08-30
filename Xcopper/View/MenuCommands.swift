import SwiftUI

extension FocusedValues {
	@Entry var operations: Operations?
}

@MainActor
extension Operations? {
	var actionsDisabled: Bool { self?.state.dialogPresented ?? true }
	var selectionDisabled: Bool { actionsDisabled || !(self?.hasSelection ?? false) }
}

@MainActor
struct MenuCommands: Commands {
	@FocusedValue(\.operations) var op

	var body: some Commands {
		if !op.actionsDisabled {
			CommandGroup(replacing: .pasteboard) {
				ActionButton(
					name: "Cut",
					image: "scissors",
					shortcut: "X",
					modifiers: .command,
					disabled: op.selectionDisabled,
					action: { op?.cut() }
				)
				ActionButton(
					name: "Copy",
					image: "document.on.document",
					shortcut: "C",
					modifiers: .command,
					disabled: op.selectionDisabled,
					action: { op?.copy() }
				)
				ActionButton(
					name: "Paste",
					image: "document.on.clipboard",
					shortcut: "V",
					modifiers: .command,
					disabled: op.actionsDisabled,
					action: { op?.paste() }
				)
				Divider()
				ActionButton(
					name: "Select all",
					image: "square.dashed.inset.filled",
					shortcut: "A",
					modifiers: .command,
					disabled: op.actionsDisabled,
					action: { op?.selectAll() }
				)
			}
		}
		CommandGroup(before: .windowSize) {
			ActionButton(
				name: "Size to fit",
				image: "arrow.up.left.and.down.right.magnifyingglass",
				shortcut: "9",
				disabled: op.actionsDisabled,
				action: { op?.scaleToFit() }
			)
			ActionButton(
				name: "Actual size",
				image: "1.magnifyingglass",
				shortcut: "0",
				disabled: op.actionsDisabled,
				action: { op?.state.setScale(4.0) }
			)
			ActionButton(
				name: "Zoom out",
				image: "minus.magnifyingglass",
				shortcut: "-",
				disabled: op.actionsDisabled,
				action: { op?.state.setScale((op?.state.magnification ?? 4.0) / 2.0) }
			)
			ActionButton(
				name: "Zoom in",
				image: "plus.magnifyingglass",
				shortcut: "=",
				disabled: op.actionsDisabled,
				action: { op?.state.setScale((op?.state.magnification ?? 4.0) * 2.0) }
			)
			Divider()
		}
		CommandMenu("Board") {
			ActionButton(
				name: "Size and layers",
				image: "square.dashed",
				shortcut: "B",
				modifiers: .command,
				disabled: op.actionsDisabled,
				action: { op?.state.boardDialogPresented = true }
			)
			Divider()
			ActionButton(
				name: "Previous layer",
				image: "square.3.layers.3d.bottom.filled",
				shortcut: "\u{19}",
				disabled: op.actionsDisabled,
				action: { op.map { op in op.state.prevLayer(op.board.stack) } }
			)
			ActionButton(
				name: "Next layer",
				image: "square.3.layers.3d.top.filled",
				shortcut: "\u{9}",
				disabled: op.actionsDisabled,
				action: { op.map { op in op.state.nextLayer(op.board.stack) } }
			)
			ActionButton(
				name: "Toggle layer",
				image: "square.3.layers.3d",
				shortcut: " ",
				disabled: op.actionsDisabled,
				action: { op.map { op in op.state.toggleVisible(op.state.layer) } }
			)
		}
		CommandMenu("Objects") {
			ActionButton(
				name: "Place footprint",
				image: "square.grid.3x3.square",
				shortcut: "F",
				modifiers: .command,
				disabled: op.actionsDisabled,
				action: { op?.state.footprintDialogPresented = true }
			)
			ActionButton(
				name: "New net",
				image: "point.3.connected.trianglepath.dotted",
				shortcut: "N",
				modifiers: [.command, .shift],
				disabled: op.actionsDisabled,
				action: { op?.state.netDialogPresented = true }
			)
			ActionButton(
				name: "Assign net",
				image: "link",
				shortcut: "L",
				modifiers: .command,
				disabled: op.selectionDisabled,
				action: { op.map { op in op.assignNet(op.state.net) } }
			)
			Divider()
			ActionButton(
				name: "Rotate left",
				image: "rotate.left",
				shortcut: "[",
				modifiers: .command,
				disabled: op.selectionDisabled,
				action: { op?.rotate(clockwise: false) }
			)
			ActionButton(
				name: "Rotate right",
				image: "rotate.right",
				shortcut: "]",
				modifiers: .command,
				disabled: op.selectionDisabled,
				action: { op?.rotate(clockwise: true) }
			)
			ActionButton(
				name: "Flip side",
				image: "arrow.left.and.right.righttriangle.left.righttriangle.right",
				shortcut: "H",
				modifiers: [.command, .shift],
				disabled: op.selectionDisabled,
				action: { op?.flip() }
			)
			ActionButton(
				name: "Duplicate",
				image: "plus.square.on.square",
				shortcut: "D",
				modifiers: .command,
				disabled: op.selectionDisabled,
				action: { op?.duplicate() }
			)
			Divider()
			ActionButton(
				name: "Delete",
				image: "trash",
				shortcut: KeyEquivalent.delete.character,
				disabled: op.selectionDisabled,
				action: { op?.delete() }
			)
		}
	}
}
