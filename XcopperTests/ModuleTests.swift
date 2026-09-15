import SwiftUI
import XCTest
@testable import Xcopper

final class ModuleTests: XCTestCase {
	private let parentURL = URL(fileURLWithPath: "/tmp/xcopper-module-tests/Parent.xcb")
	private func point(_ x: µm, _ y: µm) -> Point { Point(x: x, y: y) }
	private func source(_ stack: Stack = .classic) -> Design {
		var design = Design(board: Board(size: Size(width: 20 * .mm, height: 20 * .mm), stack: stack))
		design.nets += [Net(id: 3, name: "INPUT"), Net(id: 4, name: "PRIVATE")]
		design.place(Symbol.Spec(kind: .resistor), at: point(10 * .mm, 10 * .mm))
		design.board.footprints[0].at = point(5 * .mm, 5 * .mm)
		design.board.footprints[0].pads[0].net = 3
		design.board.footprints[0].pads[1].net = 4
		design.schematic.symbols[0].pins[0].netLabel = "#1 IN"
		design.board.traces = [Trace(start: point(5 * .mm, 5 * .mm), end: point(10 * .mm, 5 * .mm), width: 400, layer: stack.bottom, net: 3)]
		design.board.vias = [Via(at: point(10 * .mm, 5 * .mm), net: 3),
			Via(at: point(15 * .mm, 15 * .mm), net: 0)]
		design.board.holes = [Hole(at: point(10 * .mm, 15 * .mm), diameter: 2 * .mm)]
		return design
	}
	private func reader(_ sources: [String: Design]) throws -> (URL) throws -> Data {
		let data = try sources.mapValues { try JSONEncoder().encode($0) }
		return { url in try data[url.lastPathComponent].throwing("Missing \(url.lastPathComponent)") }
	}
	private func imported(_ sources: [String: Design], filenames: [String] = ["Part.xcb"], stack: Stack = .analog) throws -> Design {
		var design = Design(board: Board(size: Size(width: 100 * .mm, height: 100 * .mm), stack: stack))
		let read = try reader(sources)
		for filename in filenames { try design.importModule(filename: filename, documentURL: parentURL, read: read) }
		return design
	}

	func testLegacyJSONAndBoardDocumentRoundTripWithoutEmbeddingSources() throws {
		var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(source())) as? [String: Any])
		json.removeValue(forKey: "modules")
		XCTAssertTrue(try Document.decode(JSONSerialization.data(withJSONObject: json)).modules.isEmpty)
		let design = try imported(["Part.xcb": source()])
		XCTAssertEqual(Document.readableContentTypes, [.xcb])
		XCTAssertEqual(Document.writableContentTypes, [.xcb])
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: folder) }
		let document = Document(design: design)
		let url = folder.appendingPathComponent("Design").appendingPathExtension("xcb")
		try document.encoded().write(to: url)
		let data = try Data(contentsOf: url)
		let reopened = try Document.decode(data)
		XCTAssertEqual(reopened.modules, design.modules)
		XCTAssertEqual(reopened.board, design.board)
		XCTAssertTrue(reopened.moduleCache.contents.isEmpty)
		XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("moduleCache"))
		XCTAssertFalse(reopened.moduleErrors.isEmpty)
		XCTAssertTrue(reopened.fabrication(named: "unresolved").isEmpty)
	}

	func testOriginsRoundTripAndDefaultToZeroInOlderDocuments() throws {
		var source = source()
		source.board.origin = point(8 * .mm, 6 * .mm)
		XCTAssertEqual(try Document.decode(Document(design: source).encoded()).board.origin, source.board.origin)
		var design = try imported(["Part.xcb": source])
		design.board.origin = point(12 * .mm, 10 * .mm)
		let reopened = try Document.decode(Document(design: design).encoded())
		XCTAssertEqual(reopened.board.origin, design.board.origin)
		XCTAssertEqual(reopened.modules[0].origin, source.board.origin)
		var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Document(design: design).encoded()) as? [String: Any])
		var board = try XCTUnwrap(json["board"] as? [String: Any])
		board.removeValue(forKey: "origin")
		json["board"] = board
		var modules = try XCTUnwrap(json["modules"] as? [[String: Any]])
		modules[0].removeValue(forKey: "origin")
		json["modules"] = modules
		let legacy = try Document.decode(JSONSerialization.data(withJSONObject: json))
		XCTAssertEqual(legacy.board.origin, .zero)
		XCTAssertEqual(legacy.modules[0].origin, .zero)
	}

	func testModuleOriginPlacesAndRotatesGeometryAroundItsPosition() throws {
		var source = source()
		source.board.origin = point(8 * .mm, 6 * .mm)
		var design = try imported(["Part.xcb": source])
		let id = design.modules[0].id
		design.modules[0].layoutAt = point(50 * .mm, 40 * .mm)
		XCTAssertEqual(design.resolved.board.footprints[0].at, point(47 * .mm, 39 * .mm))
		design.rotateLayout([.module(id)], clockwise: true)
		XCTAssertEqual(design.modules[0].layoutAt, point(50 * .mm, 40 * .mm))
		let board = design.resolved.board
		XCTAssertEqual(board.footprints[0].at, point(51 * .mm, 37 * .mm))
		XCTAssertEqual(board.traces[0].start, point(51 * .mm, 37 * .mm))
		XCTAssertEqual(board.traces[0].end, point(51 * .mm, 42 * .mm))
		XCTAssertEqual(board.vias[0].at, point(51 * .mm, 42 * .mm))
		XCTAssertEqual(board.holes[0].at, point(41 * .mm, 42 * .mm))
		XCTAssertEqual(design.modules[0].bounds, Rect(origin: point(36 * .mm, 32 * .mm), size: source.board.size))
		source.board.origin = point(10 * .mm, 10 * .mm)
		var resolver = ModuleResolver(folder: parentURL.deletingLastPathComponent(), read: try reader(["Part.xcb": source]))
		resolver.reload(&design, documentURL: parentURL)
		XCTAssertEqual(design.modules[0].origin, source.board.origin)
		XCTAssertEqual(design.modules[0].layoutAt, point(50 * .mm, 40 * .mm))
		XCTAssertEqual(design.resolved.board.footprints[0].at, point(55 * .mm, 35 * .mm))
	}

	func testNestedModuleOriginsAreResolvedAtEveryLevel() throws {
		var leaf = source()
		var middle = try imported(["Part.xcb": leaf])
		middle.board.origin = point(10 * .mm, 15 * .mm)
		middle.modules[0].layoutAt = point(30 * .mm, 20 * .mm)
		middle.modules[0].layoutRotation = .r90
		leaf.board.origin = point(8 * .mm, 6 * .mm)
		var parent = try imported(["Middle.xcb": middle, "Part.xcb": leaf], filenames: ["Middle.xcb"])
		parent.modules[0].layoutAt = point(60 * .mm, 60 * .mm)
		parent.modules[0].layoutRotation = .r270
		XCTAssertEqual(parent.modules[0].origin, middle.board.origin)
		XCTAssertEqual(parent.resolved.board.footprints[0].at, point(62 * .mm, 39 * .mm))
		XCTAssertEqual(parent.resolved.board.footprints[0].rotation, .r0)
	}

	func testRepeatedInstancesSharePowerButIsolatePrivateNetsAndReferences() throws {
		let source = source()
		var design = try imported(["Part.xcb": source], filenames: ["Part.xcb", "Part.xcb"])
		_ = design.updateBoardFromSchematic()
		let resolved = design.resolved
		XCTAssertEqual(design.nets.map(\.name), ["GND", "VCC", "VEE"])
		XCTAssertEqual(resolved.board.footprints.map(\.reference), ["M1.R1", "M2.R1"])
		XCTAssertNotEqual(resolved.board.footprints[0].pads[0].net, resolved.board.footprints[1].pads[0].net)
		XCTAssertNotEqual(resolved.board.footprints[0].pads[1].net, resolved.board.footprints[1].pads[1].net)
		XCTAssertEqual(resolved.board.vias[1].net, 0)
		XCTAssertEqual(resolved.board.vias[3].net, 0)
		XCTAssertEqual(design.moduleCache.contents[design.modules[0].id]?.board.stack, .classic)
		XCTAssertEqual(resolved.board.traces.map(\.layer), [5, 5])
		XCTAssertTrue(resolved.board.objects.filter { $0.ref.kind == .via }.allSatisfy { $0.layers == 0 ... 5 })
		XCTAssertEqual(resolved.board.rules, design.board.rules)
		XCTAssertEqual(design.board.footprints.count, 0)
	}

	func testImportedViasUseParentSizesAndFollowChangesAfterProjectionIsCached() throws {
		var source = source()
		source.board.rules.viaDrill = 200
		source.board.rules.viaPad = 500
		var parent = try imported(["Part.xcb": source])
		parent.board.vias = [Via(at: point(80 * .mm, 80 * .mm), net: 0)]
		let before = parent.resolved
		parent.board.rules.viaDrill = 700
		parent.board.rules.viaPad = 1_400
		let resolved = parent.resolved.board
		XCTAssertEqual(resolved.vias.count, 3)
		for index in resolved.vias.indices {
			XCTAssertEqual(resolved.figures(on: 0, of: [.via(index)]), [.round(resolved.vias[index].at, 1_400)])
			XCTAssertEqual(resolved.drills[index], .round(resolved.vias[index].at, 700))
		}
		XCTAssertNotEqual(resolved.drills, before.board.drills)
		XCTAssertEqual(parent.moduleCache.contents[parent.modules[0].id]?.board.rules, source.board.rules)
	}

	func testConnectedIONetsStayLocalAcrossSyncAndReopen() throws {
		let module = source()
		var design = try imported(["Part.xcb": module])
		design.place(Symbol.Spec(kind: .resistor), at: point(60 * .mm, 50 * .mm))
		design.schematic.wires = [Wire(start: design.modules[0].symbol.placedPins[0].at,
			end: design.schematic.symbols[0].placedPins[0].at)]
		_ = design.updateBoardFromSchematic()
		let id = try XCTUnwrap(design.board.footprints[0].pads[0].net)
		XCTAssertEqual(design.net(id)?.name, "M1.IN")
		XCTAssertFalse(design.nets.contains { $0.id == id })
		_ = design.updateBoardFromSchematic()
		XCTAssertFalse(design.nets.contains { $0.id == id })
		var reopened = try Document.decode(Document(design: design).encoded())
		var resolver = ModuleResolver(folder: parentURL.deletingLastPathComponent(), read: try reader(["Part.xcb": module]))
		resolver.reload(&reopened, documentURL: parentURL)
		XCTAssertEqual(reopened.net(id)?.name, "M1.IN")
		XCTAssertEqual(reopened.resolved.board.footprints[1].pads[0].net, id)
	}

	func testQualifiedLabelsResolvePrivateModuleNetsWithoutPromotion() throws {
		var design = try imported(["Part.xcb": source()], filenames: ["Part.xcb", "Part.xcb"])
		design.place(Symbol.Spec(kind: .resistor), at: point(60 * .mm, 50 * .mm))
		design.schematic.symbols[0].pins[0].netLabel = "M1.PRIVATE"
		_ = design.updateBoardFromSchematic()
		let resolved = design.resolved
		let id = try XCTUnwrap(design.board.footprints[0].pads[0].net)
		XCTAssertEqual(id, resolved.board.footprints[1].pads[1].net)
		XCTAssertNotEqual(id, resolved.board.footprints[2].pads[1].net)
		XCTAssertEqual(design.net(id)?.name, "M1.PRIVATE")
		XCTAssertFalse(design.nets.contains { $0.id == id })
		XCTAssertFalse(design.net(named: "M1.PRIVATE").created)
	}

	func testStaleParentPadNetsDoNotMergeSeparateModuleInputs() throws {
		var module = Design()
		module.place(Symbol.Spec(kind: .ic, pins: 8), at: point(20 * .mm, 20 * .mm))
		module.schematic.symbols[0].pins[1].netLabel = "#1 A"
		module.schematic.symbols[0].pins[5].netLabel = "#2 B"
		_ = module.updateBoardFromSchematic()
		for staleName in ["IN1", "IN2", "LEGACY"] {
			var design = try imported(["Part.xcb": module])
			design.modules[0][netLabel: "1"] = "IN1"
			design.modules[0][netLabel: "2"] = "IN2"
			let stale = design.addNet(name: staleName)
			for (index, name) in ["IN1", "IN2"].enumerated() {
				design.place(Symbol.Spec(kind: .resistor), at: point(60 * .mm, (30 + index * 20) * .mm))
				design.schematic.symbols[index].pins[0].netLabel = name
				design.board.footprints[index].pads[0].net = stale
			}
			for syncNative in [false, true] {
				let resolved = design.moduleProjection(syncNative: syncNative).design
				let ic = try XCTUnwrap(resolved.board.footprints.first { $0.reference == "M1.U1" })
				let input1 = try XCTUnwrap(ic.pads.first { $0.name == "2" }?.net)
				let input2 = try XCTUnwrap(ic.pads.first { $0.name == "6" }?.net)
				XCTAssertEqual(resolved.net(input1)?.name, "IN1")
				XCTAssertEqual(resolved.net(input2)?.name, "IN2")
				XCTAssertNotEqual(input1, input2)
				XCTAssertEqual(resolved.board.footprints[0].pads[0].net, input1)
				XCTAssertEqual(resolved.board.footprints[1].pads[0].net, input2)
			}
			_ = design.updateBoardFromSchematic()
			let synced = design
			_ = design.updateBoardFromSchematic()
			XCTAssertEqual(design, synced)
		}
	}

	func testOpeningRemovesUnusedNetsAndPreservesCopperLabelsAndPower() throws {
		var design = source()
		let unused = design.addNet(name: "UNUSED")
		_ = design.addNet(name: "LABELED")
		design.schematic.symbols[0].pins[0].netLabel = "#1 LABELED"
		let via = design.addNet(name: "VIA")
		design.board.vias.append(Via(at: .zero, net: via))
		let trace = design.addNet(name: "TRACE")
		design.board.traces.append(Trace(start: .zero, end: point(1000, 0), width: 300, layer: 0, net: trace))
		let reopened = try Document.decode(Document(design: design).encoded())
		XCTAssertEqual(reopened.nets, design.nets.filter { $0.id != unused })
		XCTAssertEqual(reopened.board, design.board)
		XCTAssertEqual(reopened.schematic, design.schematic)
	}

	func testBufferSupplyLabelsReachTheParentInletThroughViasAndPlanes() throws {
		var buffer = Design(board: Board(size: Size(width: 40 * .mm, height: 40 * .mm), stack: .classic))
		buffer.place(Symbol.Spec(component: .ad823a), at: point(40 * .mm, 40 * .mm))
		buffer.place(Symbol.Spec(kind: .capacitor, value: "2u2"), at: point(20 * .mm, 15 * .mm))
		buffer.place(Symbol.Spec(kind: .capacitor, value: "2u2"), at: point(20 * .mm, 65 * .mm))
		let names = [
			["1": "#3 OUT1", "3": "#1 IN1", "4": "VEE", "5": "#2 IN2", "7": "#4 OUT2", "8": "VCC"],
			["1": "GND", "2": "VCC"],
			["1": "VEE", "2": "GND"],
		]
		for (index, symbol) in buffer.schematic.symbols.enumerated() {
			for (pinIndex, pin) in symbol.pins.enumerated() {
				buffer.schematic.symbols[index].pins[pinIndex].netLabel = names[index][pin.number]
			}
		}
		_ = buffer.updateBoardFromSchematic()
		let supplies = Set(["GND", "VCC", "VEE"])
		let pads = buffer.board.footprints.flatMap(\.placedPads).filter {
			buffer.net($0.net).map { supplies.contains($0.name) } ?? false
		}
		XCTAssertEqual(pads.count, 6)
		for pad in pads {
			let via = pad.at + point(0, 2 * .mm)
			buffer.board.vias.append(Via(at: via, net: pad.net))
			buffer.board.traces.append(Trace(start: pad.at, end: via, width: 250, layer: 0, net: pad.net))
		}

		var parent = try imported(["Buffer.xcb": buffer], filenames: ["Buffer.xcb"])
		parent.place(Symbol.Spec(component: .mta1563), at: point(100 * .mm, 100 * .mm))
		let rails = ["GND", "VCC", "VEE"]
		for (index, name) in rails.enumerated() {
			parent.schematic.symbols[0].pins[index].netLabel = name
		}
		_ = parent.updateBoardFromSchematic()
		let resolved = parent.resolved
		XCTAssertEqual(parent.modules[0].interface.map(\.name), ["IN1", "IN2", "OUT1", "OUT2"])
		XCTAssertEqual(resolved.board.footprints.count, 4)
		XCTAssertEqual(resolved.board.footprints[0].pads.map { parent.net($0.net)?.name }, rails)
		let amplifier = try XCTUnwrap(resolved.board.footprints.first { $0.reference == "M1.U1" })
		XCTAssertEqual(parent.net(amplifier.pads.first { $0.name == "8" }?.net)?.name, "VCC")
		XCTAssertEqual(parent.net(amplifier.pads.first { $0.name == "4" }?.net)?.name, "VEE")
		XCTAssertTrue(resolved.board.objects.filter { $0.ref.kind == .via }.allSatisfy { $0.layers == 0 ... parent.board.stack.bottom })
		let supplyIDs = Set(parent.nets.filter { supplies.contains($0.name) }.map(\.id))
		XCTAssertTrue(resolved.board.ratsnest(planes: parent.planes).filter { supplyIDs.contains($0.net) }.isEmpty)
		XCTAssertFalse(resolved.board.ratsnest().filter { supplyIDs.contains($0.net) }.isEmpty)
		var unconnected = resolved.board
		unconnected.traces = []
		XCTAssertFalse(unconnected.ratsnest(planes: parent.planes).filter { supplyIDs.contains($0.net) }.isEmpty)
	}

	func testIOExtractionOrdersPinsNumericallyAndKeepsCaseSensitiveNames() throws {
		var source = Design()
		source.place(Symbol.Spec(kind: .ic, pins: 4), at: point(20 * .mm, 20 * .mm))
		for (index, label) in ["#10 A", "#2 a", "#1 Z", "#3 IN"].enumerated() {
			source.schematic.symbols[0].pins[index].netLabel = label
		}
		let design = try imported(["Part.xcb": source])
		XCTAssertEqual(design.modules[0].interface.map(\.name), ["Z", "a", "IN", "A"])
		XCTAssertEqual(design.modules[0].symbol.pins.map(\.number), ["1", "2", "3", "10"])
		XCTAssertEqual(design.modules[0].symbol.pins.map(\.name), ["Z", "a", "IN", "A"])
		let first = design.modules[0].symbol.pins[0]
		let second = design.modules[0].symbol.pins[1]
		XCTAssertEqual(first.direction, .r180)
		XCTAssertLessThan(first.at.y, second.at.y)
		XCTAssertTrue(source.updateBoardFromSchematic().created.contains("Z"))
		XCTAssertFalse(source.nets.contains { $0.name.hasPrefix("#") })
	}

	func testIOExtractionRejectsMissingNumbersAndNames() throws {
		for label in ["#IN", "#", "#  ", "#0 IN", "#-1 IN", "#1", "#1IN", "#1 ", "#999999999999999999999 IN"] {
			var source = source()
			source.schematic.symbols[0].pins[0].netLabel = label
			XCTAssertThrowsError(try imported(["Part.xcb": source]), label)
		}
	}

	func testRepeatedIONumbersRequireMatchingNames() throws {
		var source = source()
		source.schematic.symbols[0].pins[1].netLabel = "#1 OUT"
		XCTAssertThrowsError(try imported(["Part.xcb": source])) { error in
			XCTAssertTrue((error as? Err)?.description.contains("Ambiguous") ?? false)
		}
		source.schematic.symbols[0].pins[1].netLabel = "#1 IN"
		let parent = try imported(["Part.xcb": source])
		XCTAssertEqual(parent.modules[0].interface, [IODesignator(number: 1, name: "IN")])
		XCTAssertEqual(parent.resolved.board.footprints[0].pads[0].net, parent.resolved.board.footprints[0].pads[1].net)
	}

	@MainActor
	func testParentWireAutomaticallyMapsIOToPadsTracesViasAndLeavesPrivateNetsAlone() throws {
		var design = try imported(["Part.xcb": source()])
		design.place(Symbol.Spec(kind: .resistor), at: point(60 * .mm, 50 * .mm))
		let modulePin = design.modules[0].symbol.placedPins[0].at
		let parentPin = design.schematic.symbols[0].placedPins[0].at
		let before = design.moduleCache
		let harness = EditorHarness(design: design)
		harness.perform {
			$0.design.schematic.wires = [Wire(start: modulePin, end: parentPin)]
			$0.design.schematic.symbols[0].pins[0].netLabel = "SIGNAL"
		}
		design = harness.design
		let resolved = design.resolved
		let signal = try XCTUnwrap(design.nets.first { $0.name == "SIGNAL" }?.id)
		XCTAssertEqual(design.board.footprints[0].pads[0].net, signal)
		XCTAssertEqual(resolved.board.footprints[1].pads[0].net, signal)
		XCTAssertEqual(resolved.board.traces[0].net, signal)
		XCTAssertEqual(resolved.board.vias[0].net, signal)
		XCTAssertNotEqual(resolved.board.footprints[1].pads[1].net, signal)
		XCTAssertEqual(design.moduleCache, before)
		XCTAssertFalse(resolved.board.ratsnest(planes: resolved.planes).isEmpty)
	}

	@MainActor
	func testParentCopperInheritsAnImportedPadsNetAutomatically() throws {
		var module = source()
		module.board.traces = []
		module.board.vias = []
		module.board.footprints[0].pads[1].net = nil
		let design = try imported(["Part.xcb": module])
		let pad = design.resolved.board.footprints[0].placedPads[0]
		let harness = EditorHarness(design: design)
		harness.perform {
			$0.design.board.traces.append(Trace(start: pad.at, end: pad.at + point(0, 10 * .mm),
				width: 300, layer: 0, net: nil))
		}
		XCTAssertNotNil(pad.net)
		XCTAssertEqual(harness.design.board.traces[0].net, pad.net)
		XCTAssertNotNil(harness.design.net(pad.net))
		XCTAssertFalse(harness.design.nets.contains { $0.id == pad.net })
		XCTAssertEqual(harness.design.moduleCache, design.moduleCache)
		harness.undo.undo()
		XCTAssertEqual(harness.design, design)
	}

	func testNestedPortsPropagateThroughEveryLevelAndKeepTopLevelOwnership() throws {
		let leaf = source()
		var middle = try imported(["Part.xcb": leaf], stack: .digital)
		middle.modules[0][netLabel: "1"] = "#1 NESTED"
		var parent = try imported(["Middle.xcb": middle, "Part.xcb": leaf], filenames: ["Middle.xcb"])
		parent.modules[0][netLabel: "1"] = "BUS"
		_ = parent.updateBoardFromSchematic()
		let projection = parent.moduleProjection()
		let bus = parent.nets.first { $0.name == "BUS" }?.id
		XCTAssertEqual(projection.design.board.footprints[0].reference, "M1.M1.R1")
		XCTAssertEqual(projection.design.board.footprints[0].pads[0].net, bus)
		XCTAssertEqual(projection.design.board.traces[0].net, bus)
		XCTAssertTrue(projection.owners.values.allSatisfy { $0 == parent.modules[0].id })
		XCTAssertEqual(parent.modules[0].interface.map(\.name), ["NESTED"])
	}

	func testCyclesMissingFilesMalformedFilesAndEveryStackBoundary() throws {
		var a = source(); var b = source()
		a.modules = [ModuleInstance(reference: "M1", filename: "B.xcb")]
		b.modules = [ModuleInstance(reference: "M1", filename: "A.xcb")]
		XCTAssertThrowsError(try imported(["A.xcb": a, "B.xcb": b], filenames: ["A.xcb"]))
		XCTAssertThrowsError(try imported([:]))
		XCTAssertThrowsError(try imported(["Part.xcb": source(.analog)], stack: .digital))
		b.modules = [ModuleInstance(reference: "M1", filename: "Part.xcb")]
		XCTAssertThrowsError(try imported(["B.xcb": b, "Part.xcb": source(.digital)], filenames: ["B.xcb"]))
		var parent = Design()
		XCTAssertThrowsError(try parent.importModule(filename: parentURL.lastPathComponent, documentURL: parentURL, read: reader([parentURL.lastPathComponent: source()])))
		XCTAssertThrowsError(try parent.importModule(filename: "Part.xcb", documentURL: parentURL, read: { _ in Data("bad JSON".utf8) }))
		XCTAssertTrue(parent.modules.isEmpty)
		let design = try imported(["Part.xcb": source(.digital)])
		XCTAssertFalse(design.canRestack(.classic))
		var unchanged = design
		unchanged.restack(.classic)
		XCTAssertEqual(unchanged, design)
	}

	func testReloadFailureRecoveryPinChangesAndStableNetIDs() throws {
		var source = source()
		var design = try imported(["Part.xcb": source])
		let metadata = design.modules[0]
		let old = design.resolved
		let wire = Wire(start: metadata.symbol.placedPins[0].at, end: point(70 * .mm, 70 * .mm))
		design.schematic.wires = [wire]
		var resolver = ModuleResolver(folder: parentURL.deletingLastPathComponent(), read: { _ in throw Err("Missing file") })
		resolver.reload(&design, documentURL: parentURL)
		XCTAssertEqual(design.modules[0], metadata)
		XCTAssertEqual(design.resolved.board.footprints.count, 0)
		XCTAssertEqual(design.resolved.schematic.symbols.count, 1)
		XCTAssertTrue(design.resolved.schematic.symbols[0].value.contains("Unresolved"))
		XCTAssertFalse(design.moduleErrors.isEmpty)
		source.schematic.symbols[0].pins[1].netLabel = "#2 EXTRA"
		resolver.read = try reader(["Part.xcb": source])
		resolver.reload(&design, documentURL: parentURL)
		XCTAssertTrue(design.moduleErrors.isEmpty)
		XCTAssertEqual(design.modules[0].interface.map(\.name), ["IN", "EXTRA"])
		XCTAssertEqual(design.modules[0].schematicAt, metadata.schematicAt)
		XCTAssertEqual(design.schematic.wires, [wire])
		XCTAssertFalse(design.moduleCache.notices.isEmpty)
		XCTAssertEqual(design.resolved.board.footprints[0].pads[0].net, old.board.footprints[0].pads[0].net)
	}

	func testRigidTranslationRotationSelectionAndCounterparts() throws {
		var design = try imported(["Part.xcb": source()])
		let id = design.modules[0].id
		let before = design.resolved.board
		let delta = point(5 * .mm, 4 * .mm)
		let originalSchematic = design.modules[0].schematicAt
		XCTAssertNotNil(design.moveLayout([.module(id)], by: delta, grid: 1 * .mm))
		let moved = design.resolved.board
		XCTAssertEqual(moved.traces[0].start, before.traces[0].start + delta)
		XCTAssertEqual(moved.traces[0].end, before.traces[0].end + delta)
		XCTAssertEqual(moved.vias[0].at, before.vias[0].at + delta)
		XCTAssertEqual(moved.footprints[0].at, before.footprints[0].at + delta)
		XCTAssertEqual(design.modules[0].schematicAt, originalSchematic)
		XCTAssertEqual(design.layoutRefs(at: moved.footprints[0].placedPads[0].at, layer: 0, tolerance: 1), [.module(id)])
		let pad = moved.footprints[0].placedPads[0]
		XCTAssertEqual(design.layoutRefs(in: Rect(center: pad.at, size: Size(width: 100, height: 100)), layer: 0), [.module(id)])
		XCTAssertEqual(design.schematicRef(at: design.modules[0].symbol.at, tolerance: 1), .module(id))
		XCTAssertEqual(design.footprints(for: [.module(id)]), [.module(id)])
		XCTAssertEqual(design.symbols(for: [.module(id)]), [.module(id)])
		for _ in 0 ..< 4 { design.rotateLayout([.module(id)], clockwise: true) }
		XCTAssertEqual(design.resolved.board, moved)
		design.moveSchematic([.module(id)], by: delta)
		XCTAssertEqual(design.modules[0].schematicAt, originalSchematic + delta)
		XCTAssertEqual(design.resolved.board, moved)
	}

	func testMovingAModuleKeepsParentWiresAttachedToItsSchematicPins() throws {
		var design = try imported(["Part.xcb": source()])
		let id = design.modules[0].id
		let pin = design.modules[0].symbol.placedPins[0].at
		let anchor = pin + point(20 * .mm, 0)
		design.schematic.wires = [Wire(start: pin, end: anchor)]
		design.modules[0][netLabel: "1"] = "SIGNAL"
		let layout = design.resolved.board
		let selection = try XCTUnwrap(design.moveSchematic([.module(id)], by: point(2 * .mm, 3 * .mm)))
		let movedPin = design.modules[0].symbol.placedPins[0].at
		XCTAssertEqual(movedPin, pin + point(2 * .mm, 3 * .mm))
		XCTAssertEqual(selection, [.module(id)])
		XCTAssertEqual(Netlist(design.resolved.schematic).name(at: movedPin), "SIGNAL")
		XCTAssertEqual(design.resolved.board, layout)
		XCTAssertTrue(design.schematic.wires.allSatisfy { $0.start.x == $0.end.x || $0.start.y == $0.end.y })
	}

	func testTranslationStretchesParentTracesAtImportedPadsAndVias() throws {
		for terminal in [0, 1] {
			var design = try imported(["Part.xcb": source()])
			let id = design.modules[0].id
			let imported = design.resolved.board
			let start = terminal == 0 ? imported.footprints[0].placedPads[0].at : imported.vias[0].at
			let end = start + point(20 * .mm, 0)
			design.board.traces = [Trace(start: start, end: end, width: 400, layer: 0, net: nil)]
			let delta = point(1 * .mm, 0)
			XCTAssertNotNil(design.moveLayout([.module(id)], by: delta, grid: 1 * .mm))
			XCTAssertEqual(design.board.traces.first?.start, start + delta)
			XCTAssertEqual(design.board.traces.last?.end, end)
			XCTAssertEqual(design.resolved.board.traces.last?.start, imported.traces[0].start + delta)
			let external = design.board.traces
			design.rotateLayout([.module(id)], clockwise: true)
			XCTAssertEqual(design.board.traces, external)
		}
	}

	func testDuplicationAndPairedDeletionKeepSnapshotsIndependent() throws {
		var design = try imported(["Part.xcb": source()])
		let old = design
		let ids = design.duplicateModules([design.modules[0].id], by: point(25 * .mm, 0))
		XCTAssertEqual(ids.count, 1)
		XCTAssertEqual(design.modules.count, 2)
		XCTAssertNotEqual(design.modules[0].id, design.modules[1].id)
		XCTAssertEqual(design.resolved.board.footprints.count, 2)
		XCTAssertEqual(design.resolved.schematic.symbols.count, 2)
		design.removeModules(ids)
		XCTAssertEqual(design, old)
	}

	func testImportedGeometryEntersChecksPreviewAndAllFabricationLayers() throws {
		var module = source()
		var bottom = module.board.footprints[0]
		bottom.reference = "R2"
		bottom.at = point(12 * .mm, 8 * .mm)
		bottom.flipped = true
		module.board.footprints.append(bottom)
		module.board.footprints.append(Footprint(spec: .init(kind: .header, pins: 2), reference: "J1", at: point(5 * .mm, 12 * .mm)))
		var design = try imported(["Part.xcb": module])
		let files = design.fabrication(named: "Parent")
		func file(_ suffix: String) -> String { files.first { $0.name.hasSuffix(suffix) }?.text ?? "" }
		let empty = Design(board: design.board).fabrication(named: "Parent")
		XCTAssertEqual(file(".GKO"), empty.first { $0.name.hasSuffix(".GKO") }?.text)
		for suffix in [".GTL", ".GBL", ".GTS", ".GBS", ".GTP", ".GBP", "-PTH.DRL", "-NPTH.DRL", "-BOM.csv", "-CPL.csv"] {
			XCTAssertNotEqual(file(suffix), empty.first { $0.name.hasSuffix(suffix) }?.text, suffix)
		}
		XCTAssertGreaterThan(design.resolved.board.model(Finish().shape).pieces.count, design.board.model(Finish().shape).pieces.count)
		design.modules[0].layoutAt = point(-100 * .mm, -100 * .mm)
		XCTAssertTrue(design.check().contains { $0.kind == .edge && $0.refs.contains(.module(design.modules[0].id)) })
		XCTAssertTrue(design.check().allSatisfy { $0.refs.allSatisfy { if case .module = $0 { true } else { false } } })
	}
}

extension ModuleTests {
	@MainActor
	func testDuplicateNativePartsAvoidsModuleReferencesAndReopens() throws {
		for mode in [Mode.layout, .schematic] {
			var design = try imported(["Part.xcb": source()])
			design.modules[0].reference = "R2"
			design.place(Symbol.Spec(kind: .resistor), at: point(60 * .mm, 50 * .mm))
			let harness = EditorHarness(design: design)
			harness.editor.mode = mode
			harness.layout.selection = [.footprint(0), .module(design.modules[0].id)]
			harness.schematic.selection = [.symbol(0), .module(design.modules[0].id)]
			harness.perform { $0.duplicate() }
			XCTAssertEqual(harness.design.modules.map(\.reference), ["R2", "R3"])
			let reference = mode == .layout ? harness.design.board.footprints.last?.reference : harness.design.schematic.symbols.last?.reference
			XCTAssertEqual(reference, "R4")
			XCTAssertNoThrow(try Document.decode(Document(design: harness.design).encoded()))
		}
	}

	func testInspectorReferenceEditsPreserveModuleUniquenessAndNativePairing() throws {
		var design = try imported(["Part.xcb": source()])
		design.place(Symbol.Spec(kind: .resistor), at: point(60 * .mm, 50 * .mm))
		let before = design
		design.renameReference(Ref.footprint(0), to: "M1")
		design.renameReference(Schematic.Ref.symbol(0), to: "M1")
		design.renameReference(Ref.module(design.modules[0].id), to: "R1")
		design.renameReference(Ref.module(design.modules[0].id), to: "  ")
		XCTAssertEqual(design, before)
		design.renameReference(Ref.footprint(0), to: "R2")
		design.renameReference(Schematic.Ref.symbol(0), to: "R2")
		XCTAssertEqual(design.footprints(for: [.symbol(0)]), [.footprint(0)])
		XCTAssertNoThrow(try Document.decode(Document(design: design).encoded()))
	}

	func testModuleEditsFollowIdentityAfterRemovalAndUseCurrentPosition() throws {
		var design = try imported(["Part.xcb": source()], filenames: ["Part.xcb", "Part.xcb"])
		let first = design.modules[0].id
		let second = design.modules[1].id
		design.removeModules([first])
		design.renameReference(Ref.module(second), to: "M3")
		design.positionModule(second, at: point(50 * .mm, 50 * .mm), layout: true)
		design.positionModule(second, at: point(60 * .mm, 60 * .mm), layout: true)
		XCTAssertEqual(design.modules[0].reference, "M3")
		XCTAssertEqual(design.modules[0].layoutAt, point(60 * .mm, 60 * .mm))
		let center = design.modules[0].layoutAt
		design.turnModule(second, to: .r90, layout: true)
		XCTAssertEqual(design.modules[0].layoutAt, center)
		XCTAssertEqual(design.modules[0].layoutRotation, .r90)
		let schematicCenter = design.modules[0].symbol.placedExtent.center
		design.turnModule(second, to: .r270, layout: false)
		XCTAssertEqual(design.modules[0].symbol.placedExtent.center, schematicCenter)
		let before = design
		design.renameReference(Ref.module(first), to: "Gone")
		design.positionModule(first, at: .zero, layout: true)
		design.turnModule(first, to: .r180, layout: true)
		XCTAssertEqual(design, before)
	}

	func testLayoutMarqueeHonorsWholeRunsWithAndWithoutModules() throws {
		for withModules in [false, true] {
			var design = withModules ? try imported(["Part.xcb": source()]) : Design()
			if withModules { design.modules[0].layoutAt = point(60 * .mm, 60 * .mm) }
			design.board.traces = [
				Trace(start: point(5 * .mm, 5 * .mm), end: point(10 * .mm, 5 * .mm), width: 300, layer: 0, net: nil),
				Trace(start: point(10 * .mm, 5 * .mm), end: point(20 * .mm, 5 * .mm), width: 300, layer: 0, net: nil),
			]
			let partial = Rect(from: .zero, to: point(12 * .mm, 10 * .mm))
			XCTAssertEqual(design.layoutRefs(in: partial, layer: 0), [.trace(0)])
			XCTAssertEqual(design.layoutRefs(in: partial, layer: 0, whole: true), [])
			XCTAssertEqual(design.layoutRefs(in: Rect(from: .zero, to: point(25 * .mm, 10 * .mm)), layer: 0, whole: true), [.trace(0), .trace(1)])
		}
	}

	func testNamedParentNetOverridesModulePowerAndSyncPreservesExistingNets() throws {
		var module = source()
		module.board.footprints[0].pads[0].net = 0
		module.board.traces[0].net = 0
		var design = try imported(["Part.xcb": module])
		let vbat = design.addNet(name: "VBAT")
		design.place(Symbol.Spec(kind: .resistor), at: point(60 * .mm, 50 * .mm))
		design.board.footprints[0].pads[0].net = vbat
		let pin = design.schematic.symbols[0].placedPins[0].at
		design.schematic.wires = [Wire(start: pin, end: design.modules[0].symbol.placedPins[0].at)]
		design.schematic.symbols[0].pins[0].netLabel = "VBAT"
		let existing = design.nets
		_ = design.updateBoardFromSchematic()
		XCTAssertTrue(existing.allSatisfy { design.nets.contains($0) })
		XCTAssertEqual(design.board.footprints[0].pads[0].net, vbat)
		XCTAssertEqual(design.resolved.board.footprints[1].pads[0].net, vbat)
		XCTAssertEqual(design.resolved.board.traces[0].net, vbat)
		XCTAssertEqual(design.plane(1), 0)
		XCTAssertEqual(design.plane(2), 1)
		let synced = design
		_ = design.updateBoardFromSchematic()
		XCTAssertEqual(design, synced)
	}

	func testProjectionInvalidatesForEditsAndKeepsCopiedSnapshotsIndependent() throws {
		var design = try imported(["Part.xcb": source()])
		let original = design
		let before = design.resolved
		let id = design.modules[0].id
		design.modules[0].layoutAt = design.modules[0].layoutAt + point(10 * .mm, 0)
		XCTAssertEqual(design.resolved.board.footprints[0].at, before.board.footprints[0].at + point(10 * .mm, 0))
		design.board.holes.append(Hole(at: point(90 * .mm, 90 * .mm), diameter: 3 * .mm))
		XCTAssertEqual(design.resolved.board.holes.count, before.board.holes.count + 1)
		design.modules[0][netLabel: "1"] = "NEW"
		let named = try XCTUnwrap(design.resolved.nets.first { $0.name == "NEW" })
		XCTAssertEqual(design.resolved.board.footprints[0].pads[0].net, named.id)
		let explicit = design.addNet(name: "NEW")
		XCTAssertEqual(design.resolved.board.footprints[0].pads[0].net, explicit)
		design.moduleCache.contents[id]?.board.holes.append(Hole(at: point(8 * .mm, 8 * .mm), diameter: 1 * .mm))
		XCTAssertEqual(design.resolved.board.holes.count, before.board.holes.count + 2)
		XCTAssertEqual(original.resolved, before)
		XCTAssertEqual(try Document.decode(Document(design: original).encoded()).modules, original.modules)
		design.moduleCache.errors[id] = "Missing"
		XCTAssertTrue(design.resolved.board.footprints.isEmpty)
		design = original
		XCTAssertEqual(design.resolved, before)
	}

	@MainActor
	func testOpeningModuleDocumentDoesNotMarkItEdited() async throws {
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: folder) }
		try Document(design: source()).encoded().write(to: folder.appendingPathComponent("Part.xcb"))
		let url = folder.appendingPathComponent("Parent.xcb")
		var design = Design()
		try design.importModule(filename: "Part.xcb", documentURL: url)
		try Document(design: design).encoded().write(to: url)
		let (document, _) = try await NSDocumentController.shared.openDocument(withContentsOf: url, display: true)
		defer { document.close() }
		try await Task.sleep(for: .seconds(1))
		XCTAssertFalse(document.isDocumentEdited)
		XCTAssertFalse(document.undoManager?.canUndo ?? false)
	}

	func testClipboardValidatesDestinationAndPreservesExistingSnapshots() throws {
		var destination = try imported(["Part.xcb": source()])
		let original = destination
		var changed = source()
		changed.schematic.symbols[0].pins[0].netLabel = "#1 CHANGED"
		let read = try reader(["Part.xcb": changed])
		let pasted = try destination.pasteModules(original.modules, by: point(30 * .mm, 0), documentURL: parentURL, read: read)
		XCTAssertEqual(destination.modules[0], original.modules[0])
		XCTAssertEqual(destination.moduleCache.contents[original.modules[0].id], original.moduleCache.contents[original.modules[0].id])
		XCTAssertEqual(destination.modules[1].interface.map(\.name), ["CHANGED"])
		XCTAssertTrue(pasted.contains(destination.modules[1].id))
		XCTAssertNotEqual(destination.modules[0].id, destination.modules[1].id)
		XCTAssertEqual(destination.modules[1].layoutAt, original.modules[0].layoutAt + point(30 * .mm, 0))
		let before = destination
		XCTAssertThrowsError(try destination.pasteModules(original.modules, by: .zero, documentURL: parentURL, read: { _ in throw Err("Missing in destination") }))
		XCTAssertEqual(destination, before)
		let otherURL = URL(fileURLWithPath: "/tmp/other-module-folder/Other.xcb")
		var reads: [URL] = []
		_ = try destination.pasteModules(original.modules, by: .zero, documentURL: otherURL, read: { url in
			reads.append(url)
			return try read(url)
		})
		XCTAssertTrue(reads.allSatisfy { $0.deletingLastPathComponent() == otherURL.deletingLastPathComponent().resolvingSymlinksInPath() })
	}

	func testFileReloadAfterMovingDocumentUsesNewFolderAndNeverWritesSource() throws {
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		let movedFolder = folder.appendingPathComponent("Moved")
		try FileManager.default.createDirectory(at: movedFolder, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: folder) }
		let originalData = try Document(design: source()).encoded()
		try originalData.write(to: folder.appendingPathComponent("Part.xcb"))
		let url = folder.appendingPathComponent("Parent.xcb")
		var parent = Design()
		try parent.importModule(filename: "Part.xcb", documentURL: url)
		try Document(design: parent).encoded().write(to: url)
		var reopened = try Document.decode(Data(contentsOf: url))
		var resolver = ModuleResolver(folder: folder)
		resolver.reload(&reopened, documentURL: url)
		XCTAssertEqual(reopened.resolved.board, parent.resolved.board)
		let id = parent.modules[0].id
		parent.moveLayout([.module(id)], by: point(10 * .mm, 10 * .mm), grid: 1 * .mm)
		_ = parent.updateBoardFromSchematic()
		XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("Part.xcb")), originalData)
		let movedURL = movedFolder.appendingPathComponent("Parent.xcb")
		resolver = ModuleResolver(folder: movedFolder)
		resolver.reload(&reopened, documentURL: movedURL)
		XCTAssertFalse(reopened.moduleErrors.isEmpty)
		try originalData.write(to: movedFolder.appendingPathComponent("Part.xcb"))
		resolver.reload(&reopened, documentURL: movedURL)
		XCTAssertTrue(reopened.moduleErrors.isEmpty)
	}

	@MainActor
	func testCommandsLockInternalsCopyWholeInstancesAndUndoPairedEdits() throws {
		let harness = EditorHarness(design: try imported(["Part.xcb": source()]))
		let id = harness.design.modules[0].id
		harness.layout.selection = [.module(id)]
		harness.editor.mode = .layout
		harness.operations.copy()
		XCTAssertEqual(harness.clipboard.modules, harness.design.modules)
		XCTAssertTrue(harness.clipboard.footprints.isEmpty)
		let before = harness.design
		harness.operations.assignNet(1)
		harness.operations.flip()
		XCTAssertEqual(harness.design, before)
		harness.perform { $0.duplicate() }
		let duplicated = harness.design
		XCTAssertEqual(duplicated.modules.count, 2)
		harness.undo.undo()
		XCTAssertEqual(harness.design, before)
		harness.undo.redo()
		XCTAssertEqual(harness.design, duplicated)
		harness.layout.selection = [.module(id)]
		harness.perform { $0.rotate(clockwise: true) }
		harness.undo.undo()
		XCTAssertEqual(harness.design, duplicated)
		harness.perform { $0.nudge(dx: 1) }
		harness.undo.undo()
		XCTAssertEqual(harness.design, duplicated)
		harness.perform { $0.delete() }
		XCTAssertEqual(harness.design.resolved.schematic.symbols.count, 1)
		XCTAssertEqual(harness.design.resolved.board.footprints.count, 1)
		harness.undo.undo()
		XCTAssertEqual(harness.design, duplicated)
		harness.editor.mode = .schematic
		harness.schematic.selection = [.module(id)]
		harness.operations.copy()
		XCTAssertEqual(harness.clipboard.modules.count, 1)
		XCTAssertTrue(harness.clipboard.symbols.isEmpty)
	}

	@MainActor
	func testUndoReloadRestoresCacheWithoutReadingChangedOrDeletedFiles() throws {
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: folder) }
		let sourceURL = folder.appendingPathComponent("Part.xcb")
		try Document(design: source()).encoded().write(to: sourceURL)
		let parentURL = folder.appendingPathComponent("Parent.xcb")
		var design = Design()
		try design.importModule(filename: "Part.xcb", documentURL: parentURL)
		let harness = EditorHarness(design: design)
		harness.url = parentURL
		var changed = source()
		changed.schematic.symbols[0].pins[0].netLabel = "#1 NEW"
		changed.board.traces[0].end = point(14 * .mm, 5 * .mm)
		try Document(design: changed).encoded().write(to: sourceURL)
		harness.perform { $0.reloadModules(automatic: true) }
		let reloaded = harness.design
		XCTAssertNotEqual(reloaded.resolved.board, design.resolved.board)
		try FileManager.default.removeItem(at: sourceURL)
		harness.undo.undo()
		XCTAssertEqual(harness.design, design)
		XCTAssertTrue(harness.design.moduleErrors.isEmpty)
		harness.undo.redo()
		XCTAssertEqual(harness.design, reloaded)
		XCTAssertTrue(harness.design.moduleErrors.isEmpty)
	}
}
