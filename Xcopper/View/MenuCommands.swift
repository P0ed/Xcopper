import SwiftUI

extension FocusedValues {
	@Entry var operations: Operations?
}

@MainActor
extension Operations? {
	var actionsDisabled: Bool { !(self?.editor.keysAvailable ?? false) }
	var selectionDisabled: Bool { actionsDisabled || !(self?.hasSelection ?? false) }
	var pasteDisabled: Bool { actionsDisabled || !(self?.canPaste ?? false) }
	var layoutDisabled: Bool { actionsDisabled || self?.mode != .layout }
	var counterpartDisabled: Bool { actionsDisabled || (self?.counterpartCount ?? 0) == 0 }
	var schematicDisabled: Bool { actionsDisabled || self?.mode != .schematic }
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
					disabled: op.pasteDisabled,
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
		CommandGroup(replacing: .importExport) {
			ActionButton(
				name: "Export Gerbers…",
				image: "square.and.arrow.up",
				shortcut: "E",
				modifiers: [.command, .shift],
				disabled: op.actionsDisabled,
				action: { op?.exportFabrication() }
			)
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
				action: { op?.setScale(4.0) }
			)
			ActionButton(
				name: "Zoom out",
				image: "minus.magnifyingglass",
				shortcut: "-",
				disabled: op.actionsDisabled,
				action: { op?.setScale((op?.magnification ?? 4.0) / 2.0) }
			)
			ActionButton(
				name: "Zoom in",
				image: "plus.magnifyingglass",
				shortcut: "=",
				disabled: op.actionsDisabled,
				action: { op?.setScale((op?.magnification ?? 4.0) * 2.0) }
			)
			Divider()
		}
		CommandMenu("Design") {
			ForEach(Mode.allCases, id: \.self) { mode in
				ActionButton(
					name: mode.name,
					image: mode.systemImage,
					shortcut: mode.shortcutCharacter,
					modifiers: .command,
					disabled: op.actionsDisabled,
					action: { op?.editor.mode = mode }
				)
			}
			Divider()
			ActionButton(
				name: op?.counterpartName ?? "Show footprint",
				image: op?.counterpartImage ?? "square.grid.3x3.square",
				shortcut: "J",
				modifiers: .command,
				disabled: op.counterpartDisabled,
				action: { op?.showCounterpart() }
			)
			ActionButton(
				name: "Update board from schematic",
				image: "arrow.triangle.2.circlepath",
				shortcut: "U",
				modifiers: .command,
				disabled: op.actionsDisabled,
				action: { op?.updateBoard() }
			)
		}
		CommandMenu("Board") {
			ActionButton(
				name: "Size and layers",
				image: "square.dashed",
				shortcut: "B",
				modifiers: .command,
				disabled: op.layoutDisabled,
				action: { op?.editor.sheet = .board }
			)
			Divider()
			ActionButton(
				name: "Previous layer",
				image: "square.3.layers.3d.bottom.filled",
				shortcut: "\u{19}",
				disabled: op.layoutDisabled,
				action: { op.map { op in op.layout.prevLayer(op.design.board.stack) } }
			)
			ActionButton(
				name: "Next layer",
				image: "square.3.layers.3d.top.filled",
				shortcut: "\u{9}",
				disabled: op.layoutDisabled,
				action: { op.map { op in op.layout.nextLayer(op.design.board.stack) } }
			)
		}
		CommandMenu("Objects") {
			ActionButton(
				name: "Place footprint",
				image: "square.grid.3x3.square",
				shortcut: "F",
				modifiers: .command,
				disabled: op.layoutDisabled,
				action: { op?.editor.sheet = .footprint }
			)
			ActionButton(
				name: "Place symbol",
				image: "square.on.circle",
				shortcut: "F",
				modifiers: [.command, .shift],
				disabled: op.schematicDisabled,
				action: { op?.editor.sheet = .symbol }
			)
			ActionButton(
				name: "Place label",
				image: "tag",
				shortcut: "T",
				modifiers: .command,
				disabled: op.schematicDisabled,
				action: { op?.editor.sheet = .label }
			)
			Divider()
			ActionButton(
				name: "New net",
				image: "point.3.connected.trianglepath.dotted",
				shortcut: "N",
				modifiers: [.command, .shift],
				disabled: op.layoutDisabled,
				action: { op?.editor.sheet = .net }
			)
			ActionButton(
				name: "Assign net",
				image: "link",
				shortcut: "L",
				modifiers: .command,
				disabled: op.layoutDisabled || op.selectionDisabled,
				action: { op.map { op in op.assignNet(op.layout.net) } }
			)
			Divider()
			ActionButton(
				name: "Rotate left",
				image: "rotate.left",
				shortcut: "R",
				modifiers: .shift,
				disabled: op.selectionDisabled,
				action: { op?.rotate(clockwise: false) }
			)
			ActionButton(
				name: "Rotate right",
				image: "rotate.right",
				shortcut: "R",
				disabled: op.selectionDisabled,
				action: { op?.rotate(clockwise: true) }
			)
			ActionButton(
				name: "Flip",
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
