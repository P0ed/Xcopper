import SwiftUI
import XCTest
@testable import Xcopper

@MainActor
final class SelectionEditingTests: XCTestCase {

	private func point(_ x: Double, _ y: Double) -> Point { Point(x: .mm(x), y: .mm(y)) }

	private func trace(_ width: Nm, layer: Int = 0) -> Trace {
		Trace(start: .zero, end: point(10, 0), width: width, layer: layer, net: nil)
	}

	private func design() -> Design {
		var design = Design()
		design.place(Symbol.Spec(kind: .resistor, value: "1K5"), at: point(20, 20))
		design.place(Symbol.Spec(kind: .resistor, value: "1K5"), at: point(40, 20))
		design.place(Symbol.Spec(kind: .capacitor, value: "100n"), at: point(60, 20))
		return design
	}

	func testOnlyASelectionOfOneKindGroupsForBulkEditing() {
		XCTAssertEqual(Set<Ref>([.trace(2), .trace(0)]).group?.indices, [0, 2])
		XCTAssertEqual(Set<Ref>([.trace(2), .trace(0)]).group?.kind, .trace)
		XCTAssertNil(Set<Ref>([.trace(0), .via(0)]).group)
		XCTAssertNil(Set<Ref>([.footprint(0), .module(UUID())]).group)
		XCTAssertNil(Set<Ref>([.module(UUID())]).group)
		XCTAssertNil(Set<Ref>().group)

		XCTAssertEqual(Set<Schematic.Ref>([.symbol(1), .symbol(0)]).group?.kind, .symbol)
		XCTAssertNil(Set<Schematic.Ref>([.symbol(0), .wire(0)]).group)
	}

	func testASharedBindingReadsOneValueAndWritesItToEverySelectedObject() {
		let harness = EditorHarness(design: Design())
		harness.design.board.traces = [trace(.mm(0.4)), trace(.mm(1.2)), trace(.mm(0.4))]
		let width = harness.binding(\.design).board.traces.shared([0, 2], \.width)
		XCTAssertEqual(width.wrappedValue, .mm(0.4))

		let mixed = harness.binding(\.design).board.traces.shared([0, 1], \.width)
		XCTAssertNil(mixed.wrappedValue)

		width.wrappedValue = .mm(0.8)
		XCTAssertEqual(harness.design.board.traces.map(\.width), [.mm(0.8), .mm(1.2), .mm(0.8)])
	}

	func testASharedBindingIgnoresAMixedValueAndAnIndexThatIsGone() {
		let harness = EditorHarness(design: Design())
		harness.design.board.holes = [Hole(at: .zero, diameter: .mm(1.0))]
		let drill = harness.binding(\.design).board.holes.shared([0, 7], \.diameter)
		XCTAssertEqual(drill.wrappedValue, .mm(1.0))

		drill.wrappedValue = nil
		XCTAssertEqual(harness.design.board.holes.map(\.diameter), [.mm(1.0)])

		drill.wrappedValue = .mm(2.0)
		XCTAssertEqual(harness.design.board.holes.map(\.diameter), [.mm(2.0)])
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

	func testAPowerFlagKeepsItsNetValueToItself() {
		var design = Design()
		design.place(Symbol.Spec(kind: .ground), at: point(20, 20))
		design.place(Symbol.Spec(kind: .resistor, value: "1K5"), at: point(40, 20))
		XCTAssertEqual(design.board.footprints.count, 1)

		design.setValue([Schematic.Ref.symbol(0)], to: "AGND")
		XCTAssertEqual(design.schematic.symbols.map(\.value), ["AGND", "1K5"])
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
		harness.design.schematic.wires = [Wire(start: .zero, end: point(10, 0))]
		harness.design.board.traces = [trace(.mm(0.4))]
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
		harness.design.board.traces = [trace(.mm(0.4))]

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

	func testAFlagPastesWithNothingToStandForItOnTheBoard() {
		var design = design()
		design.place(Symbol.Spec(kind: .ground), at: point(80, 20))
		let harness = EditorHarness(design: design)
		harness.editor.mode = .schematic
		harness.schematic.selection = [.symbol(3)]
		harness.perform { $0.copy() }
		XCTAssertTrue(harness.clipboard.footprints.isEmpty)

		harness.perform { $0.paste() }
		XCTAssertEqual(harness.design.schematic.symbols.map(\.kind), [.resistor, .resistor, .capacitor, .ground, .ground])
		XCTAssertEqual(harness.design.board.footprints.count, 3)
	}

	func testDeletingCopperOrAFlagLeavesTheOtherEditorAlone() {
		var design = design()
		design.place(Symbol.Spec(kind: .ground), at: point(80, 20))
		design.schematic.wires = [Wire(start: .zero, end: point(10, 0))]
		let parts = (design.schematic.symbols.count, design.board.footprints.count)

		design.deleteSchematic([.wire(0)])
		XCTAssertEqual(design.schematic.wires.count, 0)
		XCTAssertEqual(design.schematic.symbols.count, parts.0)
		XCTAssertEqual(design.board.footprints.count, parts.1)

		design.deleteSchematic([.symbol(3)])
		XCTAssertEqual(design.schematic.symbols.map(\.reference), ["R1", "R2", "C1"])
		XCTAssertEqual(design.board.footprints.count, parts.1)
	}

	func testDeletingCopperLeavesTheOtherEditorsSelectionStanding() {
		let harness = EditorHarness(design: design())
		harness.design.board.traces = [trace(.mm(0.4))]
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

	func testBothInspectorsDrawTheirBulkPropertiesForASelectionOfOneKind() {
		var design = design()
		design.board.traces = [trace(.mm(0.4)), trace(.mm(1.2), layer: 1)]
		design.board.vias = [Via(at: .zero, drill: .mm(0.5), pad: .mm(0.9), from: 0, to: 1, net: nil)]
		design.schematic.labels = [NetLabel(at: .zero, text: "SDA"), NetLabel(at: point(5, 0), text: "SCL")]

		let layout: [Set<Ref>] = [[.trace(0), .trace(1)], [.footprint(0), .footprint(2)], [.via(0)]]
		let schematic: [Set<Schematic.Ref>] = [[.symbol(0), .symbol(1)], [.label(0), .label(1)]]

		for selection in layout {
			XCTAssertNotNil(rendered { focus in
				LayoutInspector(design: .constant(design), selection: selection, focus: focus)
			})
		}
		for selection in schematic {
			XCTAssertNotNil(rendered { focus in
				SchematicInspector(
					design: .constant(design),
					netlist: Netlist(design.schematic),
					selection: selection,
					focus: focus
				)
			})
		}
	}

	private func rendered<Content: View>(
		@ViewBuilder _ content: @escaping (FocusState<Property?>.Binding) -> Content
	) -> NSImage? {
		ImageRenderer(content: InspectorHost(content: content)).nsImage
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

@MainActor
private struct InspectorHost<Content: View>: View {
	@FocusState private var focus: Property?
	@ViewBuilder var content: (FocusState<Property?>.Binding) -> Content

	var body: some View {
		VStack(alignment: .leading) { content($focus) }.frame(width: 220.0)
	}
}
