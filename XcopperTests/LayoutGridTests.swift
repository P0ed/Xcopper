import SwiftUI
import XCTest
@testable import Xcopper

@MainActor
final class LayoutGridTests: XCTestCase {
	private func point(_ x: Double, _ y: Double) -> Point { Point(x: .mm(x), y: .mm(y)) }

	private func harness() -> EditorHarness {
		let harness = EditorHarness(design: Design(board: Board(stack: .classic)))
		harness.editor.mode = .layout
		harness.layout.placementGrid = .mm(12.7)
		harness.layout.routingGrid = .mm(0.127)
		harness.design.board.footprints = [Footprint(spec: .default, reference: "R1", at: point(25.4, 25.4))]
		harness.design.board.traces = [Trace(start: point(50, 50), end: point(60, 50), width: .mm(0.4), layer: 0, net: nil)]
		harness.design.board.vias = [Via(at: point(70, 70), net: nil)]
		harness.design.board.holes = [Hole(at: point(80, 80), diameter: .mm(3.2))]
		return harness
	}

	func testGridOptionsAndToolChangesKeepBothGridsAndDisplayIndependent() {
		XCTAssertEqual(Nm.placementGrids, [.mm(1.27), .mm(2.54), .mm(12.7)])
		XCTAssertEqual(Nm.routingGrids, [.mm(0.127), .mm(0.254), .mm(0.635)])
		var state = LayoutState()
		let display = state.grid
		XCTAssertEqual(state.placementGrid, .mm(2.54))
		XCTAssertEqual(state.routingGrid, .mm(0.254))
		state.tool = .footprint
		state.activeGrid = .mm(12.7)
		XCTAssertEqual(state.activeGridOptions, Nm.placementGrids)
		state.tool = .trace
		XCTAssertEqual(state.activeGrid, .mm(0.254))
		state.activeGrid = .mm(0.127)
		state.tool = .via
		XCTAssertEqual(state.activeGrid, .mm(0.127))
		XCTAssertEqual(state.activeGridOptions, Nm.routingGrids)
		state.tool = .footprint
		XCTAssertEqual(state.activeGrid, .mm(12.7))
		XCTAssertEqual(state.grid, display)
		state.grid = .mm(25.4)
		XCTAssertEqual(state.placementGrid, .mm(12.7))
		XCTAssertEqual(state.routingGrid, .mm(0.127))
	}

	func testSelectionChoosesTheGridForItsContents() {
		var state = LayoutState()
		for refs: Set<Ref> in [[], [.footprint(0)], [.hole(0)], [.module(UUID())], [.footprint(0), .trace(0), .via(0)]] {
			state.selection = refs
			XCTAssertEqual(state.activeGrid, state.placementGrid)
			XCTAssertEqual(state.selectionGrid, state.placementGrid)
		}
		for refs: Set<Ref> in [[.trace(0)], [.via(0)], [.trace(0), .via(0)]] {
			state.selection = refs
			XCTAssertEqual(state.activeGrid, state.routingGrid)
			XCTAssertEqual(state.selectionGrid, state.routingGrid)
		}
	}

	func testNudgingUsesTheSelectedObjectsGridAndPreservesMixedGroups() {
		for (selection, distance): (Set<Ref>, Double) in [
			([.footprint(0)], 12.7), ([.hole(0)], 12.7),
			([.trace(0)], 0.127), ([.via(0)], 0.127),
			([.footprint(0), .trace(0), .via(0)], 12.7),
		] {
			let harness = harness()
			harness.layout.selection = selection
			let before = harness.design
			harness.perform { $0.nudge(dx: 1, dy: -1) }
			let after = harness.design.board
			let delta = point(distance, -distance)
			XCTAssertEqual(after.footprints[0].at, before.board.footprints[0].at + (selection.contains(.footprint(0)) ? delta : .zero))
			XCTAssertEqual(after.holes[0].at, before.board.holes[0].at + (selection.contains(.hole(0)) ? delta : .zero))
			XCTAssertEqual(after.traces[0].start, before.board.traces[0].start + (selection.contains(.trace(0)) ? delta : .zero))
			XCTAssertEqual(after.vias[0].at, before.board.vias[0].at + (selection.contains(.via(0)) ? delta : .zero))
			harness.undo.undo()
			XCTAssertEqual(harness.design, before)
		}
	}

	func testPastingUsesTheClipboardGridRegardlessOfTheCurrentSelection() {
		for (copied, selected, distance): (Ref, Ref, Double) in [
			(.trace(0), .footprint(0), 0.508),
			(.via(0), .footprint(0), 0.508),
			(.footprint(0), .via(0), 50.8),
		] {
			let harness = harness()
			harness.layout.selection = [copied]
			harness.operations.copy()
			harness.layout.selection = [selected]
			let before = harness.design.board
			harness.perform { $0.paste() }
			let delta = point(distance, distance)
			switch copied {
			case .trace: XCTAssertEqual(harness.design.board.traces.last?.start, before.traces[0].start + delta)
			case .via: XCTAssertEqual(harness.design.board.vias.last?.at, before.vias[0].at + delta)
			case .footprint: XCTAssertEqual(harness.design.board.footprints.last?.at, before.footprints[0].at + delta)
			default: XCTFail("Unexpected fixture")
			}
		}
	}

	func testCursorUsesPlacementGridForFootprintsAndRoutingGridForCopper() {
		let harness = harness()
		harness.layout.placementGrid = .mm(2.54)
		let view = LayoutView(design: harness.binding(\.design), state: harness.binding(\.layout))
		let location = point(10.7, 10.7).cg(harness.layout.viewport.magnification, origin: Layout.origin)
		for tool in [Tool.footprint, .hole] {
			harness.layout.tool = tool
			view.hover(at: location)
			XCTAssertEqual(harness.layout.viewport.cursor, point(10.16, 10.16))
		}
		for tool in [Tool.trace, .via] {
			harness.layout.tool = tool
			view.hover(at: location)
			XCTAssertEqual(harness.layout.viewport.cursor, point(10.668, 10.668))
		}
	}
}
