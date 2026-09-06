import XCTest
@testable import Xcopper

final class DeviceIdentityTests: XCTestCase {
	func testChipDevicesKeepTheirIdentityFromEitherEditor() {
		for device in [Device.resistor, .capacitor, .inductor, .diode] {
			var fromSheet = Design()
			fromSheet.place(Symbol.Spec(kind: device.symbolKind), at: .zero)
			XCTAssertEqual(fromSheet.board.footprints[0].device, device)
			XCTAssertEqual(fromSheet.board.footprints[0].package, .chip(.c1206))

			for size in Footprint.Chip.allCases {
				var fromBoard = Design()
				fromBoard.place(Footprint.Spec(chip: size, device: device), at: .zero)
				XCTAssertEqual(fromBoard.board.footprints[0].device, device)
				XCTAssertEqual(fromBoard.board.footprints[0].package, .chip(size))
				XCTAssertEqual(fromBoard.schematic.symbols[0].kind, device.symbolKind)
				XCTAssertEqual(fromBoard.board.footprints[0].reference, device.prefix + "1")
			}
		}
	}

	func testReferenceAndValueEditsCannotChangeIdentityOrAppearanceOnReload() throws {
		var design = Design()
		for spec in [
			Footprint.Spec(device: .capacitor), .init(device: .resistor),
			.init(component: .hlmpWL02), .init(component: .pomona1581), .init(component: .nkkMN12),
		] { design.place(spec, at: .zero) }
		let appearances = design.board.footprints.map(\.appearance)
		let references = ["R9", "C2/R1", "renamed", "M1/M2/C1", "C1"]
		for index in design.board.footprints.indices {
			design.renameReference(Ref.footprint(index), to: references[index])
			design.board.footprints[index].value = "Pomona 1581"
			design.schematic.symbols[index].value = "AD823"
		}

		let reopened = try Document.decode(Document(design: design).encoded())
		XCTAssertEqual(reopened, design)
		XCTAssertEqual(reopened.board.footprints.map(\.appearance), appearances)
		XCTAssertEqual(reopened.board.footprints.map(\.device), [.capacitor, .resistor, .diode, .connector, .switchContact])
		XCTAssertEqual(reopened.board.footprints.map(\.component), [nil, nil, .hlmpWL02, .pomona1581, .nkkMN12])
		XCTAssertEqual(reopened.schematic.symbols.map(\.component), [nil, nil, .hlmpWL02, .pomona1581, .nkkMN12])
	}

	func testAnExplicitUnknownDeviceStaysUnknownDespiteSuggestiveLabels() throws {
		var design = Design()
		design.board.footprints = [Footprint.chip(.c0805)]
		design.board.footprints[0].reference = "C1"
		design.board.footprints[0].value = "HLMP-WL02"
		let reopened = try Document.decode(Document(design: design).encoded())
		XCTAssertEqual(reopened.board.footprints[0].device, .unknown)
		XCTAssertNil(reopened.board.footprints[0].component)
		XCTAssertEqual(reopened.board.footprints[0].package, .chip(.c0805))
	}

	func testNestedImportsRetainCapacitorAndLibraryAppearance() throws {
		let parentURL = URL(fileURLWithPath: "/tmp/xcopper-identity-tests/Parent.xcb")
		var leaf = Design(board: Board(size: Size(width: .mm(20), height: .mm(20)), stack: .classic))
		leaf.place(Footprint.Spec(chip: .c0805, device: .capacitor), at: Point(x: .mm(5), y: .mm(5)))
		leaf.place(Footprint.Spec(component: .hlmpWL02), at: Point(x: .mm(12), y: .mm(12)))
		leaf.schematic.labels = [NetLabel(at: leaf.schematic.symbols[0].placedPins[0].at, text: "#IN")]
		let appearances = leaf.board.footprints.map(\.appearance)

		let leafData = try Document(design: leaf).encoded()
		var middle = Design()
		try middle.importModule(filename: "Leaf.xcb", documentURL: parentURL, read: { _ in leafData })
		XCTAssertEqual(middle.resolved.board.footprints.map(\.reference), ["M1/C1", "M1/D1"])
		XCTAssertEqual(middle.resolved.board.footprints.map(\.appearance), appearances)
		let middleData = try Document(design: middle).encoded()
		let read: (URL) throws -> Data = { url in
			url.lastPathComponent == "Middle.xcb" ? middleData : leafData
		}
		var parent = Design()
		let id = try parent.importModule(filename: "Middle.xcb", documentURL: parentURL, read: read)
		XCTAssertEqual(parent.resolved.board.footprints.map(\.reference), ["M1/M1/C1", "M1/M1/D1"])
		XCTAssertEqual(parent.resolved.board.footprints.map(\.appearance), appearances)
		parent.renameReference(Ref.module(id), to: "C2")
		var reopened = try Document.decode(Document(design: parent).encoded())
		var resolver = ModuleResolver(folder: parentURL.deletingLastPathComponent(), read: read)
		resolver.reload(&reopened, documentURL: parentURL)
		XCTAssertEqual(reopened.resolved.board.footprints.map(\.device), [.capacitor, .diode])
		XCTAssertEqual(reopened.resolved.board.footprints.map(\.appearance), appearances)
	}
}
