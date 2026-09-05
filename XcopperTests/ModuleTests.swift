import SwiftUI
import XCTest
@testable import Xcopper

final class ModuleTests: XCTestCase {
	private let parentURL = URL(fileURLWithPath: "/tmp/xcopper-module-tests/Parent.xcb")
	private func point(_ x: Double, _ y: Double) -> Pt { Pt(x: .mm(x), y: .mm(y)) }
	private func source(_ stack: Stack = .classic) -> Design {
		var design = Design(board: Board(size: Size(width: .mm(20), height: .mm(20)), stack: stack))
		design.nets += [Net(id: 3, name: "INPUT"), Net(id: 4, name: "PRIVATE")]
		design.place(Symbol.Spec(kind: .resistor), at: point(10, 10))
		design.board.footprints[0].at = point(5, 5)
		design.board.footprints[0].pads[0].net = 3
		design.board.footprints[0].pads[1].net = 4
		design.schematic.labels = [NetLabel(at: design.schematic.symbols[0].placedPins[0].at, text: "#IO.IN")]
		design.board.traces = [Trace(start: point(5, 5), end: point(10, 5), width: .mm(0.4), layer: stack.bottom, net: 3)]
		design.board.vias = [Via(at: point(10, 5), drill: .mm(0.5), pad: .mm(0.9), from: 0, to: stack.bottom, net: 3),
			Via(at: point(15, 15), drill: .mm(0.5), pad: .mm(0.9), from: 0, to: stack.bottom, net: 0)]
		design.board.holes = [Hole(at: point(10, 15), diameter: .mm(2))]
		return design
	}
	private func reader(_ sources: [String: Design]) throws -> (URL) throws -> Data {
		let data = try sources.mapValues { try JSONEncoder().encode($0) }
		return { url in try data[url.lastPathComponent].throwing("Missing \(url.lastPathComponent)") }
	}
	private func imported(_ sources: [String: Design], filenames: [String] = ["Part.xcm"], stack: Stack = .analog) throws -> Design {
		var design = Design(board: Board(size: Size(width: .mm(100), height: .mm(100)), stack: stack))
		let read = try reader(sources)
		for filename in filenames { try design.importModule(filename: filename, documentURL: parentURL, read: read) }
		return design
	}

	func testLegacyJSONAndBothDocumentFormatsRoundTripWithoutEmbeddingSources() throws {
		var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(source())) as? [String: Any])
		json.removeValue(forKey: "modules")
		XCTAssertTrue(try Document.decode(JSONSerialization.data(withJSONObject: json)).modules.isEmpty)
		let design = try imported(["Part.xcm": source()])
		XCTAssertTrue(Document.readableContentTypes.contains(.xcb))
		XCTAssertTrue(Document.readableContentTypes.contains(.xcm))
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: folder) }
		for type in Document.writableContentTypes {
			let document = Document(design: design)
			let url = folder.appendingPathComponent("Design").appendingPathExtension(try XCTUnwrap(type.preferredFilenameExtension))
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
	}

	func testRepeatedInstancesSharePowerButIsolatePrivateNetsAndReferences() throws {
		let source = source()
		let design = try imported(["Part.xcm": source], filenames: ["Part.xcm", "Part.xcm"])
		let resolved = design.resolved
		XCTAssertEqual(resolved.board.footprints.map(\.reference), ["M1/R1", "M2/R1"])
		XCTAssertNotEqual(resolved.board.footprints[0].pads[0].net, resolved.board.footprints[1].pads[0].net)
		XCTAssertNotEqual(resolved.board.footprints[0].pads[1].net, resolved.board.footprints[1].pads[1].net)
		XCTAssertEqual(resolved.board.vias[1].net, 0)
		XCTAssertEqual(resolved.board.vias[3].net, 0)
		XCTAssertEqual(design.moduleCache.contents[design.modules[0].id]?.board.stack, .classic)
		XCTAssertEqual(resolved.board.traces.map(\.layer), [5, 5])
		XCTAssertTrue(resolved.board.vias.allSatisfy { $0.span == 0 ... 5 })
		XCTAssertEqual(resolved.board.rules, design.board.rules)
		XCTAssertEqual(design.board.footprints.count, 0)
	}

	func testIOExtractionIsCaseSensitiveLexicalAndRejectsEmptyNames() throws {
		var source = source()
		let pin = source.schematic.symbols[0].placedPins[0].at
		source.schematic.labels += ["#IO.Z", "#IO.a", "#IO.A", "#IO.", "#IO.  ", "#io.ignored"].map { NetLabel(at: pin, text: $0) }
		let design = try imported(["Part.xcm": source])
		XCTAssertEqual(design.modules[0].interface, ["A", "IN", "Z", "a"])
		XCTAssertEqual(design.modules[0].symbol.pins.map(\.number), ["A", "IN", "Z", "a"])
	}

	func testAmbiguousRepeatedIOIsRejectedButRepeatedSameNetIsAllowed() throws {
		var source = source()
		source.schematic.labels.append(NetLabel(at: source.schematic.symbols[0].placedPins[1].at, text: "#IO.IN"))
		XCTAssertThrowsError(try imported(["Part.xcm": source])) { error in
			XCTAssertTrue((error as? Err)?.description.contains("Ambiguous") ?? false)
		}
		source.board.footprints[0].pads[1].net = 3
		XCTAssertNoThrow(try imported(["Part.xcm": source]))
	}

	func testParentWireMapsIOToPadsTracesViasAndLeavesPrivateNetsAlone() throws {
		var design = try imported(["Part.xcm": source()])
		design.place(Symbol.Spec(kind: .resistor), at: point(60, 50))
		let modulePin = design.modules[0].symbol.placedPins[0].at
		let parentPin = design.schematic.symbols[0].placedPins[0].at
		design.schematic.wires = [Wire(start: modulePin, end: parentPin)]
		design.schematic.labels = [NetLabel(at: parentPin, text: "SIGNAL")]
		let before = design.moduleCache
		_ = design.updateBoardFromSchematic()
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

	func testNestedPortsPropagateThroughEveryLevelAndKeepTopLevelOwnership() throws {
		let leaf = source()
		var middle = try imported(["Part.xcm": leaf], stack: .digital)
		middle.schematic.labels = [NetLabel(at: middle.modules[0].symbol.placedPins[0].at, text: "#IO.NESTED")]
		var parent = try imported(["Middle.xcm": middle, "Part.xcm": leaf], filenames: ["Middle.xcm"])
		parent.schematic.labels = [NetLabel(at: parent.modules[0].symbol.placedPins[0].at, text: "BUS")]
		_ = parent.updateBoardFromSchematic()
		let projection = parent.moduleProjection()
		let bus = parent.nets.first { $0.name == "BUS" }?.id
		XCTAssertEqual(projection.design.board.footprints[0].reference, "M1/M1/R1")
		XCTAssertEqual(projection.design.board.footprints[0].pads[0].net, bus)
		XCTAssertEqual(projection.design.board.traces[0].net, bus)
		XCTAssertTrue(projection.owners.values.allSatisfy { $0 == parent.modules[0].id })
		XCTAssertEqual(parent.modules[0].interface, ["NESTED"])
	}

	func testCyclesMissingFilesMalformedFilesAndEveryStackBoundary() throws {
		var a = source(); var b = source()
		a.modules = [ModuleInstance(reference: "M1", filename: "B.xcm")]
		b.modules = [ModuleInstance(reference: "M1", filename: "A.xcm")]
		XCTAssertThrowsError(try imported(["A.xcm": a, "B.xcm": b], filenames: ["A.xcm"]))
		XCTAssertThrowsError(try imported([:]))
		XCTAssertThrowsError(try imported(["Part.xcm": source(.analog)], stack: .digital))
		b.modules = [ModuleInstance(reference: "M1", filename: "Part.xcm")]
		XCTAssertThrowsError(try imported(["B.xcm": b, "Part.xcm": source(.digital)], filenames: ["B.xcm"]))
		var parent = Design()
		XCTAssertThrowsError(try parent.importModule(filename: "Part.xcm", documentURL: parentURL, read: { _ in Data("bad JSON".utf8) }))
		XCTAssertTrue(parent.modules.isEmpty)
		let design = try imported(["Part.xcm": source(.digital)])
		XCTAssertFalse(design.canRestack(.classic))
		var unchanged = design
		unchanged.restack(.classic)
		XCTAssertEqual(unchanged, design)
	}

	func testFilenameRestrictionsAndSymlinkEscapes() throws {
		let resolver = ModuleResolver(folder: parentURL.deletingLastPathComponent())
		for name in ["../Part.xcm", "/tmp/Part.xcm", "sub/Part.xcm", "sub\\Part.xcm", "", "Part.xcb", ".."] {
			XCTAssertThrowsError(try resolver.url(for: name), name)
		}
		XCTAssertEqual(try resolver.url(for: "Part.xcm").lastPathComponent, "Part.xcm")
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: folder) }
		try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("Escape.xcm"), withDestinationURL: folder.deletingLastPathComponent().appendingPathComponent("Outside.xcm"))
		XCTAssertThrowsError(try ModuleResolver(folder: folder).url(for: "Escape.xcm"))
	}

	func testReloadFailureRecoveryPinChangesAndStableNetIDs() throws {
		var source = source()
		var design = try imported(["Part.xcm": source])
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
		source.schematic.labels.append(NetLabel(at: source.schematic.symbols[0].placedPins[1].at, text: "#IO.EXTRA"))
		resolver.read = try reader(["Part.xcm": source])
		resolver.reload(&design, documentURL: parentURL)
		XCTAssertTrue(design.moduleErrors.isEmpty)
		XCTAssertEqual(design.modules[0].interface, ["EXTRA", "IN"])
		XCTAssertEqual(design.modules[0].schematicAt, metadata.schematicAt)
		XCTAssertEqual(design.schematic.wires, [wire])
		XCTAssertFalse(design.moduleCache.notices.isEmpty)
		XCTAssertEqual(design.resolved.board.footprints[0].pads[0].net, old.board.footprints[0].pads[0].net)
	}

	func testRigidTranslationRotationSelectionAndCounterparts() throws {
		var design = try imported(["Part.xcm": source()])
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
		XCTAssertEqual(design.schematicRef(at: design.modules[0].symbol.at, tolerance: 1), .module(id))
		XCTAssertEqual(design.footprints(for: [.module(id)]), [.module(id)])
		XCTAssertEqual(design.symbols(for: [.module(id)]), [.module(id)])
		for _ in 0 ..< 4 { design.rotateLayout([.module(id)], clockwise: true) }
		XCTAssertEqual(design.resolved.board, moved)
		design.moveSchematic([.module(id)], by: delta)
		XCTAssertEqual(design.modules[0].schematicAt, originalSchematic + delta)
		XCTAssertEqual(design.resolved.board, moved)
	}

	func testTranslationStretchesParentTracesAtImportedPadsAndVias() throws {
		for terminal in [0, 1] {
			var design = try imported(["Part.xcm": source()])
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
		var design = try imported(["Part.xcm": source()])
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
		var design = try imported(["Part.xcm": module])
		let files = design.fabrication(named: "Parent")
		func file(_ suffix: String) -> String { files.first { $0.name.hasSuffix(suffix) }?.text ?? "" }
		let empty = Design(board: design.board).fabrication(named: "Parent")
		XCTAssertEqual(file("Edge_Cuts.gbr"), empty.first { $0.name.hasSuffix("Edge_Cuts.gbr") }?.text)
		for suffix in ["F_Cu.gbr", "B_Cu.gbr", "F_Mask.gbr", "B_Mask.gbr", "F_Paste.gbr", "B_Paste.gbr", "PTH.drl", "NPTH.drl"] {
			XCTAssertNotEqual(file(suffix), empty.first { $0.name.hasSuffix(suffix) }?.text, suffix)
		}
		XCTAssertGreaterThan(design.resolved.board.model(Finish().shape).pieces.count, design.board.model(Finish().shape).pieces.count)
		design.modules[0].layoutAt = point(-100, -100)
		XCTAssertTrue(design.check().contains { $0.kind == .edge && $0.refs.contains(.module(design.modules[0].id)) })
		XCTAssertTrue(design.check().allSatisfy { $0.refs.allSatisfy { if case .module = $0 { true } else { false } } })
	}
}

extension ModuleTests {
	func testClipboardValidatesDestinationAndPreservesExistingSnapshots() throws {
		var destination = try imported(["Part.xcm": source()])
		let original = destination
		var changed = source()
		changed.schematic.labels[0].text = "#IO.CHANGED"
		let read = try reader(["Part.xcm": changed])
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
		try originalData.write(to: folder.appendingPathComponent("Part.xcm"))
		let url = folder.appendingPathComponent("Parent.xcb")
		var parent = Design()
		try parent.importModule(filename: "Part.xcm", documentURL: url)
		try Document(design: parent).encoded().write(to: url)
		var reopened = try Document.decode(Data(contentsOf: url))
		var resolver = ModuleResolver(folder: folder)
		resolver.reload(&reopened, documentURL: url)
		XCTAssertEqual(reopened.resolved.board, parent.resolved.board)
		let id = parent.modules[0].id
		parent.moveLayout([.module(id)], by: point(10, 10), grid: .mm(1))
		_ = parent.updateBoardFromSchematic()
		XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("Part.xcm")), originalData)
		let movedURL = movedFolder.appendingPathComponent("Parent.xcb")
		resolver = ModuleResolver(folder: movedFolder)
		resolver.reload(&reopened, documentURL: movedURL)
		XCTAssertFalse(reopened.moduleErrors.isEmpty)
		try originalData.write(to: movedFolder.appendingPathComponent("Part.xcm"))
		resolver.reload(&reopened, documentURL: movedURL)
		XCTAssertTrue(reopened.moduleErrors.isEmpty)
	}

	@MainActor
	func testCommandsLockInternalsCopyWholeInstancesAndUndoPairedEdits() throws {
		let harness = ModuleEditorHarness(design: try imported(["Part.xcm": source()]))
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
		let sourceURL = folder.appendingPathComponent("Part.xcm")
		try Document(design: source()).encoded().write(to: sourceURL)
		let parentURL = folder.appendingPathComponent("Parent.xcb")
		var design = Design()
		try design.importModule(filename: "Part.xcm", documentURL: parentURL)
		let harness = ModuleEditorHarness(design: design)
		harness.url = parentURL
		var changed = source()
		changed.schematic.labels[0].text = "#IO.NEW"
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

@MainActor
private final class ModuleEditorHarness {
	var design: Design
	var editor = EditorState()
	var layout = LayoutState()
	var schematic = SchematicState()
	var preview = PreviewState()
	var clipboard = Clipboard()
	var url: URL?
	let undo = UndoManager()
	init(design: Design) { self.design = design; undo.groupsByEvent = false }
	func replace(_ next: Design) {
		let previous = design
		guard next != previous else { return }
		undo.registerUndo(withTarget: self) { $0.replace(previous) }
		design = next
	}
	func binding<T>(_ path: ReferenceWritableKeyPath<ModuleEditorHarness, T>) -> Binding<T> {
		Binding(get: { self[keyPath: path] }, set: { self[keyPath: path] = $0 })
	}
	var operations: Operations {
		Operations(editor: binding(\.editor), layout: binding(\.layout), schematic: binding(\.schematic), preview: binding(\.preview),
			design: Binding(get: { self.design }, set: { self.replace($0) }), clipboard: binding(\.clipboard), documentURL: url, documentName: "Parent")
	}
	func perform(_ action: (Operations) -> Void) {
		undo.beginUndoGrouping()
		action(operations)
		undo.endUndoGrouping()
	}
}
