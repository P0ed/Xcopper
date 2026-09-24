import SwiftUI
import XCTest
@testable import Xcopper

@MainActor
final class SyncTests: XCTestCase {

	private func point(_ x: µm, _ y: µm) -> Point { Point(x: x, y: y) }

	private func connectedDesign() -> Design {
		var design = Design(board: Board(stack: .classic))
		for (x, y) in [(20 * µm.mm, 20 * µm.mm), (20 * .mm, 40 * .mm), (60 * .mm, 20 * .mm), (60 * .mm, 40 * .mm)] {
			design.place(Symbol.Spec(kind: .resistor), at: point(x, y))
		}
		for pair in [(0, 1), (2, 3)] {
			design.board.wires.append(Wire(
				start: design.board.footprints[pair.0].symbol.placedPins[0].at,
				end: design.board.footprints[pair.1].symbol.placedPins[0].at
			))
		}
		return design
	}

	func testRepeatedUpdatesPreserveLegacyUnnamedNetsAndRoutedCopper() throws {
		var design = connectedDesign()
		let legacy = design.addNet(name: "N$7")
		design.board.footprints[0].pads[0].net = legacy
		design.board.footprints[1].pads[0].net = legacy
		let from = design.board.footprints[0].placedPads[0].at
		let to = design.board.footprints[1].placedPads[0].at
		design.board.traces = [Trace(start: from, end: to, width: 250, layer: 0, net: legacy)]
		design.board.vias = [Via(at: to, net: legacy)]
		_ = design.updateBoardFromSchematic()
		let synced = design
		for _ in 0 ..< 3 {
			XCTAssertTrue(design.updateBoardFromSchematic().created.isEmpty)
			XCTAssertEqual(design, synced)
		}
		XCTAssertEqual(design.board.footprints[0].pads[0].net, legacy)
		XCTAssertFalse(design.board.ratsnest().contains { $0.net == legacy })

		var reopened = try Document.decode(Document(design: design).encoded())
		_ = reopened.updateBoardFromSchematic()
		XCTAssertEqual(reopened, synced)
	}

	func testNewUnnamedNetsAreIndependentOfCoordinatesAndStorageOrder() {
		var first = connectedDesign()
		var reordered = first
		reordered.board.footprints.reverse()
		reordered.board.wires.reverse()
		let delta = point(10 * .mm, 40 * .mm)
		reordered.board.footprints.modifyEach { $0.symbol.at = $0.symbol.at + delta }
		reordered.board.wires.modifyEach {
			$0.start = $0.start + delta
			$0.end = $0.end + delta
		}
		_ = first.updateBoardFromSchematic()
		_ = reordered.updateBoardFromSchematic()
		XCTAssertEqual(first.nets, reordered.nets)
		XCTAssertEqual(first.board.footprints.map(\.pads), reordered.board.footprints.reversed().map(\.pads))
		XCTAssertEqual(first.net(first.board.footprints[0].pads[0].net)?.name, "N$R1.1/R2.1")
		XCTAssertNotEqual(first.board.footprints[0].pads[0].net, first.board.footprints[2].pads[0].net)
	}

	func testRemovingFootprintsAlsoRemovesTheirSymbols() {
		var design = connectedDesign()
		design.board.footprints = []
		_ = design.updateBoardFromSchematic()
		let synced = design
		XCTAssertTrue(design.updateBoardFromSchematic().created.isEmpty)
		XCTAssertEqual(design, synced)
	}

	func testGeneratedNamesDoNotJoinAnExplicitlyNamedGroup() {
		var design = connectedDesign()
		design.board.footprints[2].symbol.pins[0].netLabel = "N$R1.1/R2.1"
		_ = design.updateBoardFromSchematic()
		XCTAssertNotEqual(design.board.footprints[0].pads[0].net, design.board.footprints[2].pads[0].net)
		let synced = design
		_ = design.updateBoardFromSchematic()
		XCTAssertEqual(design, synced)
	}

	func testInspectorEditsUpdatePadsAndUndoRedoTogether() {
		let harness = EditorHarness(design: connectedDesign())
		let original = harness.design
		harness.perform {
			$0.$design.board.footprints[0].symbol.pins[0].netLabel.wrappedValue = "SIGNAL"
		}
		let labelled = harness.design
		XCTAssertEqual(labelled.net(labelled.board.footprints[0].pads[0].net)?.name, "SIGNAL")
		harness.perform {
			$0.$design.board.footprints[0].symbol.pins[0].netLabel.wrappedValue = "RENAMED"
		}
		let renamed = harness.design
		XCTAssertEqual(renamed.net(renamed.board.footprints[1].pads[0].net)?.name, "RENAMED")
		harness.undo.undo()
		XCTAssertEqual(harness.design, labelled)
		harness.undo.undo()
		XCTAssertEqual(harness.design, original)
		harness.undo.redo()
		harness.undo.redo()
		XCTAssertEqual(harness.design, renamed)
	}

	func testMovingAndEditingTheSchematicPreservesBoardNetIDs() {
		let harness = EditorHarness(design: connectedDesign())
		harness.editor.mode = .schematic
		harness.perform { $0.design.board.footprints[0].value = "1K" }
		let synced = harness.design
		harness.schematic.selection = [.symbol(0), .symbol(1), .wire(0)]
		harness.perform { $0.nudge(dy: 1) }
		XCTAssertNotEqual(harness.design.board.symbols, synced.board.symbols)
		XCTAssertEqual(harness.design.board.footprints.map(\.pads), synced.board.footprints.map(\.pads))
		XCTAssertEqual(harness.design.board.traces, synced.board.traces)
		XCTAssertEqual(harness.design.nets, synced.nets)
		harness.perform { $0.design.board.footprints[0].symbol.pins[1].name = "UNRELATED" }
		XCTAssertEqual(harness.design.board.footprints.map(\.pads), synced.board.footprints.map(\.pads))
		XCTAssertEqual(harness.design.board.traces, synced.board.traces)
		XCTAssertEqual(harness.design.nets, synced.nets)
	}

	func testLayoutEditsDoNotResynchronizePadNets() {
		let harness = EditorHarness(design: connectedDesign())
		let original = harness.design
		harness.perform { $0.design.board.footprints[0].at = point(50 * .mm, 50 * .mm) }
		XCTAssertEqual(harness.design.nets, original.nets)
		XCTAssertEqual(harness.design.board.footprints[0].pads, original.board.footprints[0].pads)
	}

	func testSeparateGroupsDoNotReuseTheSameOldUnnamedNet() {
		var design = connectedDesign()
		let old = design.addNet(name: "N$1")
		design.board.footprints.modifyEach { $0.pads[0].net = old }
		_ = design.updateBoardFromSchematic()
		XCTAssertEqual(design.board.footprints[0].pads[0].net, old)
		XCTAssertNotEqual(design.board.footprints[2].pads[0].net, old)
		let synced = design
		_ = design.updateBoardFromSchematic()
		XCTAssertEqual(design, synced)
	}
}
