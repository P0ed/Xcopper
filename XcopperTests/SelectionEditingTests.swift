import SwiftUI
import XCTest
@testable import Xcopper

@MainActor
final class SelectionEditingTests: XCTestCase {

	private func point(_ x: µm, _ y: µm) -> Point { Point(x: x, y: y) }

	private func trace(_ width: µm, layer: Int = 0) -> Trace {
		Trace(start: .zero, end: point(10 * .mm, 0), width: width, layer: layer, net: nil)
	}

	private func design() -> Design {
		var design = Design()
		design.place(Symbol.Spec(kind: .resistor, value: "1K5"), at: point(20 * .mm, 20 * .mm))
		design.place(Symbol.Spec(kind: .resistor, value: "1K5"), at: point(40 * .mm, 20 * .mm))
		design.place(Symbol.Spec(kind: .capacitor, value: "100n"), at: point(60 * .mm, 20 * .mm))
		return design
	}

	func testBothEditorsFinishSelectionAndMovementAtTheReleasePosition() throws {
		func check<State: SelectionState>(_ initial: State, ref: State.SelectionRef) throws {
			var state = initial
			state.selection = [ref]
			state.beginSelect(at: .zero, mode: .union)
			state.updateSelect(to: point(2 * .mm, 2 * .mm))
			state.beginSelect(at: point(2 * .mm, 2 * .mm), mode: .replace)
			let selection = try XCTUnwrap(state.endSelect(at: point(4 * .mm, 4 * .mm)))
			XCTAssertEqual(selection.rect, Rect(from: .zero, to: point(4 * .mm, 4 * .mm)))
			XCTAssertEqual(selection.initial, [ref])
			XCTAssertEqual(selection.mode, .union)
			XCTAssertNil(state.selectSession)
			XCTAssertNil(state.endSelect(at: .zero))

			state.beginMove(at: .zero)
			state.updateMove(to: point(2 * .mm, 2 * .mm))
			let move = try XCTUnwrap(state.endMove(at: point(4 * .mm, 4 * .mm)))
			XCTAssertEqual(move.delta, point(4 * .mm, 4 * .mm))
			XCTAssertNil(state.moveSession)
			XCTAssertNil(state.endMove(at: .zero))

			state.beginMove(at: .zero)
			state.updateMove(to: point(2 * .mm, 2 * .mm))
			XCTAssertFalse(try XCTUnwrap(state.endMove(at: .zero)).didMove)
		}

		try check(LayoutState(), ref: .via(0))
		try check(SchematicState(), ref: .symbol(0))
	}

	func testUndoGroupRunsWithoutAManagerAndCombinesEditsWhenOneIsPresent() {
		var invoked = false
		let manager: UndoManager? = nil
		manager.undoGroup("Edit") { invoked = true }
		XCTAssertTrue(invoked)

		let original = design()
		let harness = EditorHarness(design: original)
		harness.undo.undoGroup("Edit") {
			harness.operations.design.setValue([Schematic.Ref.symbol(0)], to: "4K7")
			harness.operations.design.setValue([Schematic.Ref.symbol(1)], to: "10K")
		}
		XCTAssertEqual(harness.undo.undoActionName, "Edit")
		XCTAssertEqual(harness.undo.groupingLevel, 0)
		harness.undo.undo()
		XCTAssertEqual(harness.design, original)
		XCTAssertFalse(harness.undo.canUndo)
	}

	func testOnlyASelectionOfOneKindGroupsForBulkEditing() {
		XCTAssertEqual(Set<Ref>([.trace(2), .trace(0)]).group?.indices, [0, 2])
		XCTAssertEqual(Set<Ref>([.trace(2), .trace(0)]).group?.kind, .trace)
		XCTAssertNil(Set<Ref>([.trace(0), .via(0)]).group)
		XCTAssertNil(Set<Ref>([.footprint(0), .module(UUID())]).group)
		XCTAssertNil(Set<Ref>([.module(UUID())]).group)
		XCTAssertNil(Set<Ref>([.pad(0, 0), .pad(1, 0)]).group)
		XCTAssertNil(Set<Ref>().group)

		XCTAssertEqual(Set<Schematic.Ref>([.symbol(1), .symbol(0)]).group?.kind, .symbol)
		XCTAssertNil(Set<Schematic.Ref>([.symbol(0), .wire(0)]).group)
	}

	func testClickingAPadSelectsItsFootprintBeforeSelectingThePad() {
		let design = design()
		let at = design.board.footprints[0].placedPads[0].at
		let first = design.layoutRefs(at: at, layer: 0, tolerance: 0)
		XCTAssertEqual(first, [.footprint(0)])
		XCTAssertEqual(design.layoutRefs(at: at, layer: 0, tolerance: 0, selection: first), [.pad(0, 0)])
		XCTAssertEqual(design.layoutRefs(at: at, layer: 0, tolerance: 0, whole: true, selection: first), [.pad(0, 0)])
		XCTAssertEqual(design.layoutRefs(at: at, layer: 0, tolerance: 0, selection: [.footprint(1)]), first)
		XCTAssertEqual(design.layoutRefs(at: at, layer: 0, tolerance: 0, selection: [.pad(0, 0)]), first)

		let harness = EditorHarness(design: design)
		harness.editor.mode = .layout
		harness.layout.selection = [.pad(0, 0)]
		harness.operations.selectAll()
		XCTAssertEqual(harness.layout.selection, [.footprint(0), .footprint(1), .footprint(2)])
	}

	func testPadNetsComeFromSchematicLabelsAndCannotBeAssignedInLayout() {
		let design = design()
		let harness = EditorHarness(design: design)
		harness.editor.mode = .schematic
		harness.perform {
			$0.design.schematic.labels = [NetLabel(at: design.schematic.symbols[0].placedPins[0].at, text: "SIGNAL")]
		}
		let original = harness.design
		XCTAssertEqual(original.net(original.board[net: .pad(0, 0)])?.name, "SIGNAL")
		XCTAssertNil(original.board[net: .pad(0, 1)])
		harness.editor.mode = .layout
		for selection: Set<Ref> in [[.pad(0, 0)], [.pad(0, 0), .pad(1, 1)], [.footprint(0)]] {
			harness.layout.selection = selection
			XCTAssertFalse(harness.operations.canAssignNet)
			harness.operations.assignNet(1)
			harness.operations.assignNet(nil)
			XCTAssertEqual(harness.design, original)
		}
		var board = original.board
		board[net: .pad(0, 0)] = nil
		board[net: .footprint(0)] = 1
		XCTAssertEqual(board, original.board)
		harness.undo.undo()
		XCTAssertEqual(harness.design, design)
	}

	func testLayoutCanStillAssignNetsToTracesAndVias() {
		var design = design()
		design.board.traces = [trace(400)]
		design.board.vias = [Via(at: .zero, net: nil)]
		let harness = EditorHarness(design: design)
		harness.editor.mode = .layout
		harness.layout.selection = [.trace(0), .via(0)]
		XCTAssertTrue(harness.operations.canAssignNet)
		harness.perform { $0.assignNet(1) }
		XCTAssertEqual(harness.design.board.traces[0].net, 1)
		XCTAssertEqual(harness.design.board.vias[0].net, 1)
		XCTAssertEqual(harness.design.board.footprints, design.board.footprints)
		harness.layout.selection.insert(.pad(0, 0))
		XCTAssertFalse(harness.operations.canAssignNet)
		harness.operations.assignNet(nil)
		XCTAssertEqual(harness.design.board.traces[0].net, 1)
		harness.undo.undo()
		XCTAssertEqual(harness.design, design)
	}

	func testPadSelectionDoesNotMoveDeleteOrCopyItsFootprint() {
		let original = design()
		let harness = EditorHarness(design: original)
		harness.editor.mode = .layout
		harness.layout.selection = [.pad(0, 0)]
		harness.clipboard.holes = [Hole(at: .zero, diameter: 1 * .mm)]
		let clipboard = harness.clipboard
		XCTAssertTrue(harness.operations.hasPadSelection)
		XCTAssertFalse(harness.operations.hasModuleSelection)
		harness.operations.nudge(dx: 1)
		harness.operations.rotate(clockwise: true)
		harness.operations.flip()
		harness.operations.duplicate()
		harness.operations.cut()
		XCTAssertEqual(harness.design, original)
		XCTAssertEqual(harness.layout.selection, [.pad(0, 0)])
		XCTAssertEqual(harness.clipboard, clipboard)
		XCTAssertFalse(harness.undo.canUndo)
	}

	func testLabelsSelectedTogetherEditAsOne() throws {
		let harness = EditorHarness(design: design())
		harness.design.schematic.labels = [
			NetLabel(at: point(20 * .mm, 40 * .mm), text: "GND"),
			NetLabel(at: point(40 * .mm, 40 * .mm), text: "VCC"),
			NetLabel(at: point(60 * .mm, 40 * .mm), text: "GND"),
		]
		let group = try XCTUnwrap(Set<Schematic.Ref>([.label(1), .label(0)]).group)
		XCTAssertEqual(group.kind, .label)
		XCTAssertEqual(group.indices, [0, 1])
		XCTAssertNil(Set<Schematic.Ref>([.label(0), .symbol(0)]).group)
		let net = harness.binding(\.design).schematic.labels.shared(group.indices, \.text)
		XCTAssertNil(net.wrappedValue)
		net.wrappedValue = "AGND"
		XCTAssertEqual(harness.design.schematic.labels.map(\.text), ["AGND", "AGND", "GND"])
		XCTAssertEqual(harness.design.board, design().board)
	}

	func testDuplicatingALabelPreservesItsNetAndCanBeUndone() {
		var design = design()
		design.schematic.labels = [NetLabel(at: point(20 * .mm, 40 * .mm), text: "VEE")]
		let harness = EditorHarness(design: design)
		harness.editor.mode = .schematic
		harness.schematic.selection = [.label(0)]
		harness.perform { $0.duplicate() }
		XCTAssertEqual(harness.schematic.selection, [.label(1)])
		XCTAssertEqual(harness.design.schematic.labels[1], modifying(design.schematic.labels[0]) {
			$0.at = $0.at + harness.operations.offset
		})
		XCTAssertEqual(harness.design.board, design.board)
		XCTAssertEqual(harness.design.schematic.symbols, design.schematic.symbols)
		harness.undo.undo()
		XCTAssertEqual(harness.design, design)
	}

	func testASharedBindingReadsOneValueAndWritesItToEverySelectedObject() {
		let harness = EditorHarness(design: Design())
		harness.design.board.traces = [trace(400), trace(1_200), trace(400)]
		let width = harness.binding(\.design).board.traces.shared([0, 2], \.width)
		XCTAssertEqual(width.wrappedValue, 400)

		let mixed = harness.binding(\.design).board.traces.shared([0, 1], \.width)
		XCTAssertNil(mixed.wrappedValue)

		width.wrappedValue = 800
		XCTAssertEqual(harness.design.board.traces.map(\.width), [800, 1_200, 800])
	}

	func testASharedBindingIgnoresAMixedValueAndAnIndexThatIsGone() {
		let harness = EditorHarness(design: Design())
		harness.design.board.holes = [Hole(at: .zero, diameter: 1 * .mm)]
		let drill = harness.binding(\.design).board.holes.shared([0, 7], \.diameter)
		XCTAssertEqual(drill.wrappedValue, 1 * .mm)

		drill.wrappedValue = nil
		XCTAssertEqual(harness.design.board.holes.map(\.diameter), [1 * .mm])

		drill.wrappedValue = 2 * .mm
		XCTAssertEqual(harness.design.board.holes.map(\.diameter), [2 * .mm])
	}

	func testEditingTheValueOfSelectedSymbolsCarriesToTheirFootprints() {
		let harness = EditorHarness(design: design())
		let value = harness.binding(\.design).value(of: [.symbol(0), .symbol(1)])
		XCTAssertEqual(value.wrappedValue, "1K5")

		value.wrappedValue = "4K7"
		XCTAssertEqual(harness.design.schematic.symbols.map(\.value), ["4K7", "4K7", "100n"])
		XCTAssertEqual(harness.design.board.footprints.map(\.value), ["4K7", "4K7", "100n"])
	}

	func testEditingTheValueOfAFootprintCarriesBackToItsSymbol() {
		let harness = EditorHarness(design: design())
		let value = harness.binding(\.design).value(of: Ref.footprint(2))
		XCTAssertEqual(value.wrappedValue, "100n")

		value.wrappedValue = "220n"
		XCTAssertEqual(harness.design.schematic.symbols.map(\.value), ["1K5", "1K5", "220n"])
		XCTAssertEqual(harness.design.board.footprints.map(\.value), ["1K5", "1K5", "220n"])
	}

	func testAValueSharedByBothHalvesReadsAsMixedAcrossUnlikeParts() {
		var design = design()
		XCTAssertNil(design.values(of: [Schematic.Ref.symbol(0), .symbol(2)]).shared)
		XCTAssertEqual(design.values(of: [Ref.footprint(0), .footprint(1)]).shared, "1K5")

		design.setValue([Schematic.Ref.symbol(0), .symbol(2)], to: "10n")
		XCTAssertEqual(design.schematic.symbols.map(\.value), ["10n", "1K5", "10n"])
		XCTAssertEqual(design.board.footprints.map(\.value), ["10n", "1K5", "10n"])
	}

	func testAPowerLabelKeepsItsNetNameToItself() {
		var design = Design()
		design.schematic.labels = [NetLabel(at: point(20 * .mm, 20 * .mm), text: "GND")]
		design.place(Symbol.Spec(kind: .resistor, value: "1K5"), at: point(40 * .mm, 20 * .mm))
		XCTAssertEqual(design.board.footprints.count, 1)

		design.schematic.labels[0].text = "AGND"
		XCTAssertEqual(design.schematic.labels.map(\.text), ["AGND"])
		XCTAssertEqual(design.schematic.symbols.map(\.value), ["1K5"])
		XCTAssertEqual(design.board.footprints.map(\.value), ["1K5"])
	}

	func testRenamingEitherHalfRenamesThePartOnBothSides() {
		var design = design()
		design.renameReference(Schematic.Ref.symbol(0), to: "R9")
		XCTAssertEqual(design.schematic.symbols.map(\.reference), ["R9", "R2", "C1"])
		XCTAssertEqual(design.board.footprints.map(\.reference), ["R9", "R2", "C1"])
		XCTAssertEqual(design.footprints(for: [.symbol(0)]), [.footprint(0)])

		design.renameReference(Ref.footprint(2), to: "C7")
		XCTAssertEqual(design.schematic.symbols.map(\.reference), ["R9", "R2", "C7"])
		XCTAssertEqual(design.board.footprints.map(\.reference), ["R9", "R2", "C7"])
		XCTAssertEqual(design.symbols(for: [.footprint(2)]), [.symbol(2)])
	}

	func testDeletingEitherHalfTakesThePartOffBothSides() {
		let harness = EditorHarness(design: design())
		harness.design.schematic.wires = [Wire(start: .zero, end: point(10 * .mm, 0))]
		harness.design.board.traces = [trace(400)]
		let before = harness.design

		harness.editor.mode = .layout
		harness.layout.selection = [.footprint(0)]
		harness.schematic.selection = [.symbol(0)]
		harness.perform { $0.delete() }
		XCTAssertEqual(harness.design.board.footprints.map(\.reference), ["R2", "C1"])
		XCTAssertEqual(harness.design.schematic.symbols.map(\.reference), ["R2", "C1"])
		XCTAssertEqual(harness.design.schematic.wires.count, 1)
		XCTAssertEqual(harness.design.board.traces.count, 1)
		XCTAssertTrue(harness.layout.selection.isEmpty)
		XCTAssertTrue(harness.schematic.selection.isEmpty)

		harness.undo.undo()
		XCTAssertEqual(harness.design, before)

		harness.editor.mode = .schematic
		harness.schematic.selection = [.symbol(2)]
		harness.perform { $0.delete() }
		XCTAssertEqual(harness.design.schematic.symbols.map(\.reference), ["R1", "R2"])
		XCTAssertEqual(harness.design.board.footprints.map(\.reference), ["R1", "R2"])
	}

	func testCopyingEitherHalfPutsTheWholePartOnTheClipboard() {
		let harness = EditorHarness(design: design())
		harness.design.board.traces = [trace(400)]

		harness.editor.mode = .layout
		harness.layout.selection = [.footprint(0)]
		harness.operations.copy()
		XCTAssertEqual(harness.clipboard.footprints.map(\.reference), ["R1"])
		XCTAssertEqual(harness.clipboard.symbols.map(\.reference), ["R1"])
		XCTAssertFalse(harness.clipboard.schematicIsEmpty)

		harness.layout.selection = [.trace(0)]
		harness.operations.copy()
		XCTAssertTrue(harness.clipboard.symbols.isEmpty)
		XCTAssertTrue(harness.clipboard.schematicIsEmpty)
	}

	func testCuttingAndPastingAPartBringsBackBothHalvesAsOnePart() {
		let harness = EditorHarness(design: design())
		harness.editor.mode = .layout
		harness.layout.selection = [.footprint(0)]
		harness.perform { $0.cut() }
		XCTAssertEqual(harness.design.board.footprints.map(\.reference), ["R2", "C1"])
		XCTAssertEqual(harness.design.schematic.symbols.map(\.reference), ["R2", "C1"])

		harness.perform { $0.paste() }
		XCTAssertEqual(harness.design.board.footprints.map(\.reference), ["R2", "C1", "R1"])
		XCTAssertEqual(harness.design.schematic.symbols.map(\.reference), ["R2", "C1", "R1"])
		XCTAssertEqual(harness.design.footprints(for: [.symbol(2)]), [.footprint(2)])
		XCTAssertEqual(harness.design.values(of: [Ref.footprint(2)]), ["1K5"])
		XCTAssertEqual(harness.layout.selection, [.footprint(2)])
	}

	func testPastingOnTheSheetParksTheFootprintTheSymbolStandsFor() {
		let harness = EditorHarness(design: design())
		harness.editor.mode = .schematic
		harness.schematic.selection = [.symbol(2)]
		harness.perform { $0.copy() }
		harness.perform { $0.paste() }
		XCTAssertEqual(harness.design.schematic.symbols.map(\.reference), ["R1", "R2", "C1", "C2"])
		XCTAssertEqual(harness.design.board.footprints.map(\.reference), ["R1", "R2", "C1", "C2"])
		XCTAssertEqual(harness.design.footprints(for: [.symbol(3)]), [.footprint(3)])
		XCTAssertNotEqual(harness.design.board.footprints[3].at, harness.design.board.footprints[2].at)
	}

	func testDuplicatingEitherHalfDuplicatesTheWholePart() {
		let harness = EditorHarness(design: design())
		harness.editor.mode = .layout
		harness.layout.selection = [.footprint(2)]
		harness.perform { $0.duplicate() }
		XCTAssertEqual(harness.design.board.footprints.map(\.reference), ["R1", "R2", "C1", "C2"])
		XCTAssertEqual(harness.design.schematic.symbols.map(\.reference), ["R1", "R2", "C1", "C2"])
		XCTAssertEqual(harness.design.footprints(for: [.symbol(3)]), [.footprint(3)])
		XCTAssertEqual(harness.layout.selection, [.footprint(3)])

		harness.editor.mode = .schematic
		harness.schematic.selection = [.symbol(0)]
		harness.perform { $0.duplicate() }
		XCTAssertEqual(harness.design.schematic.symbols.map(\.reference), ["R1", "R2", "C1", "C2", "R3"])
		XCTAssertEqual(harness.design.board.footprints.map(\.reference), ["R1", "R2", "C1", "C2", "R3"])
		XCTAssertEqual(harness.design.values(of: [Ref.footprint(4)]), ["1K5"])
	}

	func testALabelPastesWithNothingToStandForItOnTheBoard() {
		var design = design()
		design.schematic.labels = [NetLabel(at: point(80 * .mm, 20 * .mm), text: "GND")]
		let harness = EditorHarness(design: design)
		harness.editor.mode = .schematic
		harness.schematic.selection = [.label(0)]
		harness.perform { $0.copy() }
		XCTAssertTrue(harness.clipboard.footprints.isEmpty)

		harness.perform { $0.paste() }
		XCTAssertEqual(harness.design.schematic.symbols.map(\.kind), [.resistor, .resistor, .capacitor])
		XCTAssertEqual(harness.design.schematic.labels.map(\.text), ["GND", "GND"])
		XCTAssertEqual(harness.design.schematic.labels[1].at, point(80 * .mm, 20 * .mm) + harness.operations.offset)
		XCTAssertEqual(harness.schematic.selection, [.label(1)])
		XCTAssertEqual(harness.design.board, design.board)
	}

	func testDeletingCopperOrALabelLeavesTheOtherEditorAlone() {
		var design = design()
		design.schematic.labels = [NetLabel(at: point(80 * .mm, 20 * .mm), text: "GND")]
		design.schematic.wires = [Wire(start: .zero, end: point(10 * .mm, 0))]
		let parts = (design.schematic.symbols.count, design.board.footprints.count)

		design.deleteSchematic([.wire(0)])
		XCTAssertEqual(design.schematic.wires.count, 0)
		XCTAssertEqual(design.schematic.symbols.count, parts.0)
		XCTAssertEqual(design.board.footprints.count, parts.1)

		design.deleteSchematic([.label(0)])
		XCTAssertTrue(design.schematic.labels.isEmpty)
		XCTAssertEqual(design.schematic.symbols.map(\.reference), ["R1", "R2", "C1"])
		XCTAssertEqual(design.board.footprints.count, parts.1)
	}

	func testDeletingCopperLeavesTheOtherEditorsSelectionStanding() {
		let harness = EditorHarness(design: design())
		harness.design.board.traces = [trace(400)]
		harness.editor.mode = .layout
		harness.layout.selection = [.trace(0)]
		harness.schematic.selection = [.symbol(1)]
		harness.perform { $0.delete() }
		XCTAssertTrue(harness.layout.selection.isEmpty)
		XCTAssertEqual(harness.schematic.selection, [.symbol(1)])

		harness.layout.selection = [.footprint(1)]
		harness.perform { $0.delete() }
		XCTAssertTrue(harness.schematic.selection.isEmpty)
	}

	func testAPartWillNotTakeAReferenceAnotherPartAlreadyHolds() {
		var design = design()
		let before = design
		design.renameReference(Ref.footprint(0), to: "R2")
		design.renameReference(Schematic.Ref.symbol(0), to: "C1")
		design.renameReference(Ref.footprint(0), to: "  ")
		XCTAssertEqual(design, before)

		design.renameReference(Ref.footprint(0), to: "R7")
		XCTAssertEqual(design.schematic.symbols.map(\.reference), ["R7", "R2", "C1"])
		XCTAssertEqual(design.board.footprints.map(\.reference), ["R7", "R2", "C1"])
	}

	func testFindSelectsPartsWhoseReferenceOrValueStartsWithTheQuery() {
		let design = design()
		XCTAssertEqual(design.schematicRefs(matching: "C"), [.symbol(2)])
		XCTAssertEqual(design.layoutRefs(matching: "c1"), [.footprint(2)])
		XCTAssertEqual(design.schematicRefs(matching: "R"), [.symbol(0), .symbol(1)])
		XCTAssertEqual(design.layoutRefs(matching: "1k"), [.footprint(0), .footprint(1)])
		XCTAssertEqual(design.schematicRefs(matching: "R2"), [.symbol(1)])
		XCTAssertEqual(design.schematicRefs(matching: "500"), [])
		XCTAssertEqual(design.schematicRefs(matching: ""), [])
	}

	func testFindReplacesTheSelectionInTheEditorItIsUsedIn() {
		let harness = EditorHarness(design: design())
		harness.editor.mode = .schematic
		harness.perform { $0.find("R") }
		XCTAssertEqual(harness.schematic.selection, [.symbol(0), .symbol(1)])
		XCTAssertEqual(harness.schematic.viewport.pending, harness.design.schematicBounds([.symbol(0), .symbol(1)])?.center)

		harness.editor.mode = .layout
		harness.perform { $0.find("100n") }
		XCTAssertEqual(harness.layout.selection, [.footprint(2)])

		harness.perform { $0.find("nothing") }
		XCTAssertEqual(harness.layout.selection, [])
		XCTAssertEqual(harness.schematic.selection, [.symbol(0), .symbol(1)])
	}
}
