import SwiftUI
import XCTest
@testable import Xcopper

final class BoardViaTests: XCTestCase {
	private func point(_ x: Double, _ y: Double) -> Point { Point(x: .mm(x), y: .mm(y)) }

	private func design() -> Design {
		var design = Design(board: Board(stack: .classic))
		design.board.rules.viaDrill = .mm(0.3)
		design.board.rules.viaPad = .mm(0.6)
		design.board.vias = [
			Via(at: point(10, 10), net: 0),
			Via(at: point(20, 10), net: 0),
		]
		return design
	}

	func testChangingBoardSizesUpdatesCopperDrillsSelectionAndRouting() {
		var board = design().board
		let edge = point(10.6, 10)
		XCTAssertNil(board.hitTest(at: edge, layer: 0, tolerance: 0))
		XCTAssertFalse(board.isTerminal(edge, layer: 0))

		board.rules.viaDrill = .mm(0.8)
		board.rules.viaPad = .mm(1.4)
		let copper = [Figure.round(point(10, 10), .mm(1.4)), .round(point(20, 10), .mm(1.4))]
		for layer in board.stack.copper {
			XCTAssertEqual(board.figures(on: layer).map { $0.0 }, copper)
			XCTAssertEqual(board.figures(on: layer, of: [.via(0)]), [copper[0]])
			XCTAssertEqual(board.clearances(on: layer, net: 1), copper.map { $0.outset(.mm(0.3)) })
		}
		XCTAssertEqual(board.drills, [.round(point(10, 10), .mm(0.8)), .round(point(20, 10), .mm(0.8))])
		XCTAssertEqual(board.hitTest(at: edge, layer: 0, tolerance: 0), .via(0))
		XCTAssertTrue(board.isTerminal(edge, layer: 0))
		XCTAssertEqual(board.bounds(of: [.via(0)]), copper[0].bounds)
		XCTAssertEqual(board.occupied, copper.map(\.bounds))
		XCTAssertEqual(board.objects.map(\.figure), copper)
		XCTAssertEqual(board.routing().terminals.map(\.figure), copper)
	}

	@MainActor
	func testBoardSettingsUndoAndRedoSizesAndNewConnectionsTogether() {
		var design = design()
		design.board.vias[0].net = nil
		design.board.traces = [Trace(start: point(10, 10.8), end: point(15, 10.8), width: .mm(0.2), layer: 0, net: 1)]
		let harness = EditorHarness(design: design)
		var rules = design.board.rules
		rules.viaDrill = .mm(0.7)
		rules.viaPad = .mm(1.6)
		let size = Size(width: .mm(80), height: .mm(60))
		harness.perform { $0.configureBoard(size: size, stack: .digital, rules: rules) }
		let changed = harness.design
		XCTAssertEqual(changed.board.rules, rules)
		XCTAssertEqual(changed.board.size, size)
		XCTAssertEqual(changed.board.stack, .digital)
		XCTAssertEqual(changed.board.vias.map(\.net), [1, 0])
		XCTAssertEqual(changed.board.objects.filter { $0.ref.kind == .via }.map(\.layers), [0 ... 3, 0 ... 3])

		harness.undo.undo()
		XCTAssertEqual(harness.design, design)
		XCTAssertFalse(harness.undo.canUndo)
		harness.undo.redo()
		XCTAssertEqual(harness.design, changed)
	}

	@MainActor
	func testViasPastedFromAnotherBoardUseTheDestinationSizesAndFullStack() {
		let source = EditorHarness(design: design())
		source.editor.mode = .layout
		source.layout.selection = [.via(0)]
		source.operations.copy()
		var design = design()
		design.restack(.analog)
		design.board.rules.viaDrill = .mm(0.7)
		design.board.rules.viaPad = .mm(1.3)
		let harness = EditorHarness(design: design)
		harness.editor.mode = .layout
		harness.clipboard = source.clipboard
		harness.perform { $0.paste() }
		XCTAssertEqual(harness.design.board.vias.count, 3)
		XCTAssertEqual(harness.design.board.drills.map { $0.bounds.size.width }, Array(repeating: .mm(0.7), count: 3))
		XCTAssertEqual(harness.design.board.figures(on: 0).map { $0.0.bounds.size.width }, Array(repeating: .mm(1.3), count: 3))
		for layer in harness.design.board.stack.copper {
			XCTAssertEqual(harness.design.board.figures(on: layer, of: [.via(2)]).count, 1)
		}
	}

	func testLegacyBlindAndBuriedViasBecomeThroughViasAcrossStackChanges() throws {
		var original = design()
		original.restack(.analog)
		var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Document(design: original).encoded()) as? [String: Any])
		var board = try XCTUnwrap(json["board"] as? [String: Any])
		var vias = try XCTUnwrap(board["vias"] as? [[String: Any]])
		vias[0]["from"] = 0
		vias[0]["to"] = 1
		vias[1]["from"] = 1
		vias[1]["to"] = 2
		board["vias"] = vias
		json["board"] = board
		var decoded = try Document.decode(JSONSerialization.data(withJSONObject: json))
		XCTAssertEqual(decoded, original)

		for stack in [Stack.analog, .digital, .classic, .analog] {
			decoded.restack(stack)
			let board = decoded.board
			XCTAssertEqual(board.vias, original.board.vias, "restacking must preserve every via")
			XCTAssertEqual(board.objects.map(\.layers), Array(repeating: stack.top ... stack.bottom, count: 2))
			XCTAssertEqual(board.routing().terminals.map(\.layers), Array(repeating: stack.top ... stack.bottom, count: 2))
			let files = decoded.fabrication(named: "Board")
			for layer in stack.copper {
				XCTAssertEqual(board.figures(on: layer).count, 2)
				for (index, via) in board.vias.enumerated() {
					XCTAssertEqual(board.figures(on: layer, of: [.via(index)]), [.round(via.at, board.rules.viaPad)])
					XCTAssertTrue(board.isTerminal(via.at, layer: layer))
					XCTAssertEqual(board.snapTarget(near: via.at, layer: layer, radius: 0)?.0, via.at)
				}
				let copper = try XCTUnwrap(files.first { $0.name == "Board." + stack.copperFile(of: layer) }?.text)
				let drawnCopper = try XCTUnwrap(copper.components(separatedBy: "%LPD*%").last)
				XCTAssertEqual(drawnCopper.components(separatedBy: "D03*").count - 1, 2)
			}
			let drills = try XCTUnwrap(files.first { $0.name == "Board-PTH.DRL" }?.text)
			XCTAssertTrue(drills.contains("TF.FileFunction,Plated,1,\(stack.count),PTH"))
		}

		let saved = try Document(design: decoded).encoded()
		let savedJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
		let savedBoard = try XCTUnwrap(savedJSON["board"] as? [String: Any])
		let savedVias = try XCTUnwrap(savedBoard["vias"] as? [[String: Any]])
		XCTAssertTrue(savedVias.allSatisfy { $0["from"] == nil && $0["to"] == nil })
		XCTAssertEqual(try Document.decode(saved), decoded)
	}

	func testLegacyViaOverridesUseSavedBoardSizesAndAreNoLongerWritten() throws {
		var design = design()
		design.board.rules.viaDrill = .mm(0.4)
		design.board.rules.viaPad = .mm(0.8)
		var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Document(design: design).encoded()) as? [String: Any])
		var board = try XCTUnwrap(json["board"] as? [String: Any])
		var vias = try XCTUnwrap(board["vias"] as? [[String: Any]])
		vias[0]["drill"] = Nm.mm(0.2)
		vias[0]["pad"] = Nm.mm(0.5)
		vias[1]["drill"] = Nm.mm(0.9)
		vias[1]["pad"] = Nm.mm(1.5)
		board["vias"] = vias
		json["board"] = board

		let decoded = try Document.decode(JSONSerialization.data(withJSONObject: json))
		XCTAssertEqual(decoded, design)
		XCTAssertEqual(decoded.board.drills.map { $0.bounds.size.width }, [.mm(0.4), .mm(0.4)])
		let saved = try Document(design: decoded).encoded()
		let savedJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
		let savedBoard = try XCTUnwrap(savedJSON["board"] as? [String: Any])
		let savedVias = try XCTUnwrap(savedBoard["vias"] as? [[String: Any]])
		XCTAssertTrue(savedVias.allSatisfy { $0["drill"] == nil && $0["pad"] == nil })
		XCTAssertEqual(try Document.decode(saved), decoded)
	}

	func testEveryViaExportsWithTheCurrentBoardDrillAndPad() throws {
		var design = design()
		for (drill, pad) in [(0.3, 0.6), (0.7, 1.4)] {
			design.board.rules.viaDrill = .mm(drill)
			design.board.rules.viaPad = .mm(pad)
			let files = design.fabrication(named: "Board")
			for suffix in ["GTL", "GBL"] {
				let copper = try XCTUnwrap(files.first { $0.name == "Board." + suffix }?.text)
				XCTAssertTrue(copper.contains(String(format: "%%ADD10C,%.6f*%%", pad)))
				XCTAssertEqual(copper.components(separatedBy: "D03*").count - 1, 2)
			}
			let drills = try XCTUnwrap(files.first { $0.name == "Board-PTH.DRL" }?.text)
			XCTAssertTrue(drills.contains(String(format: "T1C%.3f", drill)))
			XCTAssertFalse(drills.contains("T2"))
			XCTAssertEqual(drills.split(separator: "\n").count { $0.hasPrefix("X") }, 2)
		}
	}
}
