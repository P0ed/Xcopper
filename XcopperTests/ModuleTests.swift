import SwiftUI
import XCTest
@testable import Xcopper

final class ModuleTests: XCTestCase {
	private let parentURL = URL(fileURLWithPath: "/tmp/xcopper-module-tests/Parent.xcb")
	private func point(_ x: Double, _ y: Double) -> Point { Point(x: .mm(x), y: .mm(y)) }
	private func source(_ stack: Stack = .classic) -> Design {
		var design = Design(board: Board(size: Size(width: .mm(20), height: .mm(20)), stack: stack))
		design.nets += [Net(id: 3, name: "INPUT"), Net(id: 4, name: "PRIVATE")]
		design.place(Symbol.Spec(kind: .resistor), at: point(10, 10))
		design.board.footprints[0].at = point(5, 5)
		design.board.footprints[0].pads[0].net = 3
		design.board.footprints[0].pads[1].net = 4
		design.schematic.labels = [NetLabel(at: design.schematic.symbols[0].placedPins[0].at, text: "#IN")]
		design.board.traces = [Trace(start: point(5, 5), end: point(10, 5), width: .mm(0.4), layer: stack.bottom, net: 3)]
		design.board.vias = [Via(at: point(10, 5), net: 3),
			Via(at: point(15, 15), net: 0)]
		design.board.holes = [Hole(at: point(10, 15), diameter: .mm(2))]
		return design
	}
	private func reader(_ sources: [String: Design]) throws -> (URL) throws -> Data {
		let data = try sources.mapValues { try JSONEncoder().encode($0) }
		return { url in try data[url.lastPathComponent].throwing("Missing \(url.lastPathComponent)") }
	}
	private func imported(_ sources: [String: Design], filenames: [String] = ["Part.xcb"], stack: Stack = .analog) throws -> Design {
		var design = Design(board: Board(size: Size(width: .mm(100), height: .mm(100)), stack: stack))
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

	func testRepeatedInstancesSharePowerButIsolatePrivateNetsAndReferences() throws {
		let source = source()
		let design = try imported(["Part.xcb": source], filenames: ["Part.xcb", "Part.xcb"])
		let resolved = design.resolved
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
		source.board.rules.viaDrill = .mm(0.2)
		source.board.rules.viaPad = .mm(0.5)
		var parent = try imported(["Part.xcb": source])
		parent.board.vias = [Via(at: point(80, 80), net: 0)]
		let before = parent.resolved
		parent.board.rules.viaDrill = .mm(0.7)
		parent.board.rules.viaPad = .mm(1.4)
		let resolved = parent.resolved.board
		XCTAssertEqual(resolved.vias.count, 3)
		for index in resolved.vias.indices {
			XCTAssertEqual(resolved.figures(on: 0, of: [.via(index)]), [.round(resolved.vias[index].at, .mm(1.4))])
			XCTAssertEqual(resolved.drills[index], .round(resolved.vias[index].at, .mm(0.7)))
		}
		XCTAssertNotEqual(resolved.drills, before.board.drills)
		XCTAssertEqual(parent.moduleCache.contents[parent.modules[0].id]?.board.rules, source.board.rules)
	}

	func testBufferSupplyLabelsReachTheParentInletThroughViasAndPlanes() throws {
		var buffer = Design(board: Board(size: Size(width: .mm(40), height: .mm(40)), stack: .classic))
		buffer.place(Symbol.Spec(component: .ad823a), at: point(40, 40))
		buffer.place(Symbol.Spec(kind: .capacitor, value: "2u2"), at: point(20, 15))
		buffer.place(Symbol.Spec(kind: .capacitor, value: "2u2"), at: point(20, 65))
		let names = [
			["1": "#OUT1", "3": "#IN1", "4": "VEE", "5": "#IN2", "7": "#OUT2", "8": "VCC"],
			["1": "GND", "2": "VCC"],
			["1": "VEE", "2": "GND"],
		]
		for (index, symbol) in buffer.schematic.symbols.enumerated() {
			for pin in symbol.placedPins {
				if let name = names[index][pin.number] {
					buffer.schematic.labels.append(NetLabel(at: pin.at, text: name))
				}
			}
		}
		_ = buffer.updateBoardFromSchematic()
		let supplies = Set(["GND", "VCC", "VEE"])
		let pads = buffer.board.footprints.flatMap(\.placedPads).filter {
			buffer.net($0.net).map { supplies.contains($0.name) } ?? false
		}
		XCTAssertEqual(pads.count, 6)
		for pad in pads {
			let via = pad.at + point(0, 2)
			buffer.board.vias.append(Via(at: via, net: pad.net))
			buffer.board.traces.append(Trace(start: pad.at, end: via, width: .mm(0.25), layer: 0, net: pad.net))
		}

		var parent = try imported(["Buffer.xcb": buffer], filenames: ["Buffer.xcb"])
		parent.place(Symbol.Spec(component: .mta1563), at: point(100, 100))
		let rails = ["GND", "VCC", "VEE"]
		for (pin, name) in zip(parent.schematic.symbols[0].placedPins, rails) {
			parent.schematic.labels.append(NetLabel(at: pin.at, text: name))
		}
		_ = parent.updateBoardFromSchematic()
		let resolved = parent.resolved
		XCTAssertEqual(parent.modules[0].interface, ["IN1", "IN2", "OUT1", "OUT2"])
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

	func testIOExtractionIsCaseSensitiveLexicalAndRejectsEmptyNames() throws {
		var source = source()
		let pin = source.schematic.symbols[0].placedPins[0].at
		source.schematic.labels += ["#Z", "#a", "#A", "#", "#  "].map { NetLabel(at: pin, text: $0) }
		let design = try imported(["Part.xcb": source])
		XCTAssertEqual(design.modules[0].interface, ["A", "IN", "Z", "a"])
		XCTAssertEqual(design.modules[0].symbol.pins.map(\.number), ["A", "IN", "Z", "a"])
	}

	func testAmbiguousRepeatedIOIsRejectedButRepeatedSameNetIsAllowed() throws {
		var source = source()
		source.schematic.labels.append(NetLabel(at: source.schematic.symbols[0].placedPins[1].at, text: "#IN"))
		XCTAssertThrowsError(try imported(["Part.xcb": source])) { error in
			XCTAssertTrue((error as? Err)?.description.contains("Ambiguous") ?? false)
		}
		source.board.footprints[0].pads[1].net = 3
		XCTAssertNoThrow(try imported(["Part.xcb": source]))
	}

	@MainActor
	func testParentWireAutomaticallyMapsIOToPadsTracesViasAndLeavesPrivateNetsAlone() throws {
		var design = try imported(["Part.xcb": source()])
		design.place(Symbol.Spec(kind: .resistor), at: point(60, 50))
		let modulePin = design.modules[0].symbol.placedPins[0].at
		let parentPin = design.schematic.symbols[0].placedPins[0].at
		let before = design.moduleCache
		let harness = EditorHarness(design: design)
		harness.perform {
			$0.design.schematic.wires = [Wire(start: modulePin, end: parentPin)]
			$0.design.schematic.labels = [NetLabel(at: parentPin, text: "SIGNAL")]
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
			$0.design.board.traces.append(Trace(start: pad.at, end: pad.at + point(0, 10),
				width: .mm(0.3), layer: 0, net: nil))
		}
		XCTAssertNotNil(pad.net)
		XCTAssertEqual(harness.design.board.traces[0].net, pad.net)
		XCTAssertNotNil(harness.design.net(pad.net))
		XCTAssertEqual(harness.design.moduleCache, design.moduleCache)
		harness.undo.undo()
		XCTAssertEqual(harness.design, design)
	}

	func testNestedPortsPropagateThroughEveryLevelAndKeepTopLevelOwnership() throws {
		let leaf = source()
		var middle = try imported(["Part.xcb": leaf], stack: .digital)
		middle.schematic.labels = [NetLabel(at: middle.modules[0].symbol.placedPins[0].at, text: "#NESTED")]
		var parent = try imported(["Middle.xcb": middle, "Part.xcb": leaf], filenames: ["Middle.xcb"])
		parent.schematic.labels = [NetLabel(at: parent.modules[0].symbol.placedPins[0].at, text: "BUS")]
		_ = parent.updateBoardFromSchematic()
		let projection = parent.moduleProjection()
		let bus = parent.nets.first { $0.name == "BUS" }?.id
		XCTAssertEqual(projection.design.board.footprints[0].reference, "M1.M1.R1")
		XCTAssertEqual(projection.design.board.footprints[0].pads[0].net, bus)
		XCTAssertEqual(projection.design.board.traces[0].net, bus)
		XCTAssertTrue(projection.owners.values.allSatisfy { $0 == parent.modules[0].id })
		XCTAssertEqual(parent.modules[0].interface, ["NESTED"])
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
		let wire = Wire(start: metadata.symbol.placedPins[0].at, end: point(70, 70))
		design.schematic.wires = [wire]
		var resolver = ModuleResolver(folder: parentURL.deletingLastPathComponent(), read: { _ in throw Err("Missing file") })
		resolver.reload(&design, documentURL: parentURL)
		XCTAssertEqual(design.modules[0], metadata)
		XCTAssertEqual(design.resolved.board.footprints.count, 0)
		XCTAssertEqual(design.resolved.schematic.symbols.count, 1)
		XCTAssertTrue(design.resolved.schematic.symbols[0].value.contains("Unresolved"))
		XCTAssertFalse(design.moduleErrors.isEmpty)
		source.schematic.labels.append(NetLabel(at: source.schematic.symbols[0].placedPins[1].at, text: "#EXTRA"))
		resolver.read = try reader(["Part.xcb": source])
		resolver.reload(&design, documentURL: parentURL)
		XCTAssertTrue(design.moduleErrors.isEmpty)
		XCTAssertEqual(design.modules[0].interface, ["EXTRA", "IN"])
		XCTAssertEqual(design.modules[0].schematicAt, metadata.schematicAt)
		XCTAssertEqual(design.schematic.wires, [wire])
		XCTAssertFalse(design.moduleCache.notices.isEmpty)
		XCTAssertEqual(design.resolved.board.footprints[0].pads[0].net, old.board.footprints[0].pads[0].net)
	}

	func testRigidTranslationRotationSelectionAndCounterparts() throws {
		var design = try imported(["Part.xcb": source()])
		let id = design.modules[0].id
		let before = design.resolved.board
		let delta = point(5, 4)
		let originalSchematic = design.modules[0].schematicAt
		XCTAssertNotNil(design.moveLayout([.module(id)], by: delta, grid: .mm(1)))
		let moved = design.resolved.board
		XCTAssertEqual(moved.traces[0].start, before.traces[0].start + delta)
		XCTAssertEqual(moved.traces[0].end, before.traces[0].end + delta)
		XCTAssertEqual(moved.vias[0].at, before.vias[0].at + delta)
		XCTAssertEqual(moved.footprints[0].at, before.footprints[0].at + delta)
		XCTAssertEqual(design.modules[0].schematicAt, originalSchematic)
		XCTAssertEqual(design.layoutRefs(at: moved.footprints[0].placedPads[0].at, layer: 0, tolerance: 1), [.module(id)])
		let pad = moved.footprints[0].placedPads[0]
		XCTAssertEqual(design.layoutRefs(in: Rect(center: pad.at, size: Size(width: .mm(0.1), height: .mm(0.1))), layer: 0), [.module(id)])
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
		let anchor = pin + point(20, 0)
		design.schematic.wires = [Wire(start: pin, end: anchor)]
		design.schematic.labels = [NetLabel(at: anchor, text: "SIGNAL")]
		let layout = design.resolved.board
		let selection = try XCTUnwrap(design.moveSchematic([.module(id)], by: point(2, 3)))
		let movedPin = design.modules[0].symbol.placedPins[0].at
		XCTAssertEqual(movedPin, pin + point(2, 3))
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
			let end = start + point(20, 0)
			design.board.traces = [Trace(start: start, end: end, width: .mm(0.4), layer: 0, net: nil)]
			let delta = point(1, 0)
			XCTAssertNotNil(design.moveLayout([.module(id)], by: delta, grid: .mm(1)))
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
		let ids = design.duplicateModules([design.modules[0].id], by: point(25, 0))
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
		bottom.at = point(12, 8)
		bottom.flipped = true
		module.board.footprints.append(bottom)
		module.board.footprints.append(Footprint(spec: .init(kind: .header, pins: 2), reference: "J1", at: point(5, 12)))
		var design = try imported(["Part.xcb": module])
		let files = design.fabrication(named: "Parent")
		func file(_ suffix: String) -> String { files.first { $0.name.hasSuffix(suffix) }?.text ?? "" }
		let empty = Design(board: design.board).fabrication(named: "Parent")
		XCTAssertEqual(file(".GKO"), empty.first { $0.name.hasSuffix(".GKO") }?.text)
		for suffix in [".GTL", ".GBL", ".GTS", ".GBS", ".GTP", ".GBP", "-PTH.DRL", "-NPTH.DRL", "-BOM.csv", "-CPL.csv"] {
			XCTAssertNotEqual(file(suffix), empty.first { $0.name.hasSuffix(suffix) }?.text, suffix)
		}
		XCTAssertGreaterThan(design.resolved.board.model(Finish().shape).pieces.count, design.board.model(Finish().shape).pieces.count)
		design.modules[0].layoutAt = point(-100, -100)
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
			design.place(Symbol.Spec(kind: .resistor), at: point(60, 50))
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
		design.place(Symbol.Spec(kind: .resistor), at: point(60, 50))
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
		design.positionModule(second, at: point(50, 50), layout: true)
		design.positionModule(second, at: point(60, 60), layout: true)
		XCTAssertEqual(design.modules[0].reference, "M3")
		XCTAssertEqual(design.modules[0].layoutAt, point(60, 60))
		let center = design.modules[0].bounds.center
		design.turnModule(second, to: .r90, layout: true)
		XCTAssertEqual(design.modules[0].bounds.center, center)
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
			if withModules { design.modules[0].layoutAt = point(60, 60) }
			design.board.traces = [
				Trace(start: point(5, 5), end: point(10, 5), width: .mm(0.3), layer: 0, net: nil),
				Trace(start: point(10, 5), end: point(20, 5), width: .mm(0.3), layer: 0, net: nil),
			]
			let partial = Rect(from: .zero, to: point(12, 10))
			XCTAssertEqual(design.layoutRefs(in: partial, layer: 0), [.trace(0)])
			XCTAssertEqual(design.layoutRefs(in: partial, layer: 0, whole: true), [])
			XCTAssertEqual(design.layoutRefs(in: Rect(from: .zero, to: point(25, 10)), layer: 0, whole: true), [.trace(0), .trace(1)])
		}
	}

	func testNamedParentNetOverridesModulePowerAndSyncPreservesExistingNets() throws {
		var module = source()
		module.board.footprints[0].pads[0].net = 0
		module.board.traces[0].net = 0
		var design = try imported(["Part.xcb": module])
		let vbat = design.addNet(name: "VBAT")
		design.place(Symbol.Spec(kind: .resistor), at: point(60, 50))
		design.board.footprints[0].pads[0].net = vbat
		let pin = design.schematic.symbols[0].placedPins[0].at
		design.schematic.wires = [Wire(start: pin, end: design.modules[0].symbol.placedPins[0].at)]
		design.schematic.labels = [NetLabel(at: pin, text: "VBAT")]
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
		design.modules[0].layoutAt = design.modules[0].layoutAt + point(10, 0)
		XCTAssertEqual(design.resolved.board.footprints[0].at, before.board.footprints[0].at + point(10, 0))
		design.board.holes.append(Hole(at: point(90, 90), diameter: .mm(3)))
		XCTAssertEqual(design.resolved.board.holes.count, before.board.holes.count + 1)
		design.schematic.labels = [NetLabel(at: design.modules[0].symbol.placedPins[0].at, text: "NEW")]
		let named = try XCTUnwrap(design.resolved.nets.first { $0.name == "NEW" })
		XCTAssertEqual(design.resolved.board.footprints[0].pads[0].net, named.id)
		let explicit = design.addNet(name: "NEW")
		XCTAssertEqual(design.resolved.board.footprints[0].pads[0].net, explicit)
		design.moduleCache.contents[id]?.board.holes.append(Hole(at: point(8, 8), diameter: .mm(1)))
		XCTAssertEqual(design.resolved.board.holes.count, before.board.holes.count + 2)
		XCTAssertEqual(original.resolved, before)
		XCTAssertEqual(try Document.decode(Document(design: original).encoded()).modules, original.modules)
		design.moduleCache.errors[id] = "Missing"
		XCTAssertTrue(design.resolved.board.footprints.isEmpty)
		design = original
		XCTAssertEqual(design.resolved, before)
	}

	@MainActor
	func testSizeOnlyResizeRemainsAvailableWithAnIncompatibleModule() throws {
		var design = Design(board: Board(stack: .classic))
		design.modules = [ModuleInstance(reference: "M1", filename: "Missing.xcb", layerCount: 4)]
		let harness = EditorHarness(design: design)
		let size = Size(width: .mm(120), height: .mm(80))
		harness.perform { $0.configureBoard(size: size, stack: .classic, rules: design.board.rules) }
		XCTAssertEqual(harness.design.board.size, size)
		XCTAssertEqual(harness.design.board.stack, .classic)
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
		changed.schematic.labels[0].text = "#CHANGED"
		let read = try reader(["Part.xcb": changed])
		let pasted = try destination.pasteModules(original.modules, by: point(30, 0), documentURL: parentURL, read: read)
		XCTAssertEqual(destination.modules[0], original.modules[0])
		XCTAssertEqual(destination.moduleCache.contents[original.modules[0].id], original.moduleCache.contents[original.modules[0].id])
		XCTAssertEqual(destination.modules[1].interface, ["CHANGED"])
		XCTAssertTrue(pasted.contains(destination.modules[1].id))
		XCTAssertNotEqual(destination.modules[0].id, destination.modules[1].id)
		XCTAssertEqual(destination.modules[1].layoutAt, original.modules[0].layoutAt + point(30, 0))
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
		parent.moveLayout([.module(id)], by: point(10, 10), grid: .mm(1))
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
		changed.schematic.labels[0].text = "#NEW"
		changed.board.traces[0].end = point(14, 5)
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
