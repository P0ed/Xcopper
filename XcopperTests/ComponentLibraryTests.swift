import XCTest
@testable import Xcopper

final class ComponentLibraryTests: XCTestCase {

	func testLibraryContainsEveryRequestedPart() {
		XCTAssertEqual(Component.allCases.map(\.name), [
			"AD823", "AD823A", "AD633", "ADR5045", "ADG419",
			"CD4013", "CD4029", "CD4070", "CD4093", "CD40106",
			"SSI2162", "THAT2180", "Pomona 1581", "Bourns 51",
			"MTA-156-3", "MTA-156-4", "HLMP-WL02", "NKK MN12",
			"NKK MN15", "1N4148W", "BCM847DS", "BCM857DS", "SSM2212",
		])
	}

	func testSymbolsCarryDataSheetPinNamesAndPartValues() {
		for component in Component.allCases {
			let symbol = component.makeSymbol()
			let pins = symbol.pins.sorted(by: numericPinOrder)
			XCTAssertEqual(symbol.value, component.name)
			XCTAssertEqual(pins.map(\.name), component.pinNames, component.name)
			XCTAssertEqual(pins.map(\.number), (1 ... component.pinNames.count).map(String.init), component.name)
		}

		XCTAssertEqual(Component.ad633.pinNames, ["Y1", "Y2", "-VS", "Z", "W", "+VS", "X1", "X2"])
		XCTAssertEqual(Component.bcm847DS.pinNames, ["E1", "B1", "C2", "E2", "B2", "C1"])
		XCTAssertEqual(Component.ssm2212.pinNames, ["C1", "B1", "E1", "NIC", "NIC", "E2", "B2", "C2"])
	}

	func testEveryBoardPartHasPadsForEverySymbolPin() throws {
		for component in Component.layoutCases {
			let footprint = try XCTUnwrap(component.makeFootprint(), component.name)
			XCTAssertEqual(footprint.value, component.name)
			XCTAssertEqual(
				Set(footprint.pads.map(\.name)),
				Set((1 ... component.pinNames.count).map(String.init)),
				component.name
			)
		}
	}

	func testEveryPartSitsOnExactlyOneShelfAndNoShelfIsEmpty() {
		let shelved = Component.Category.allCases.flatMap(\.components)
		XCTAssertEqual(Set(shelved), Set(Component.allCases))
		XCTAssertEqual(shelved.count, Component.allCases.count)
		XCTAssertTrue(Component.Category.allCases.allSatisfy { !$0.components.isEmpty })

		let onBoard = Component.Category.allCases.flatMap(\.layoutComponents)
		XCTAssertEqual(Set(onBoard), Set(Component.layoutCases))

		XCTAssertEqual(Component.ad823.category, .opAmps)
		XCTAssertEqual(Component.ad633.category, .multipliers)
		XCTAssertEqual(Component.that2180.category, .multipliers)
		XCTAssertEqual(Component.cd40106.category, .logic)
		XCTAssertEqual(Component.adg419.category, .switches)
		XCTAssertEqual(Component.nkkMN15.category, .switches)
		XCTAssertEqual(Component.bourns51.category, .panelControls)
		XCTAssertEqual(Component.pomona1581.category, .connectors)
		XCTAssertEqual(Component.ssm2212.category, .discretes)
	}

	func testEveryLibraryPartHasAFootprint() {
		XCTAssertEqual(Component.layoutCases, Component.allCases)
		XCTAssertTrue(Component.allCases.allSatisfy { $0.makeFootprint() != nil })
	}

	func testMechanicalFootprintGeometry() throws {
		let pomona = try XCTUnwrap(Component.pomona1581.makeFootprint())
		XCTAssertEqual(pomona.pads.count, 2)
		XCTAssertEqual(pomona.pads.map(\.name), ["1", "1"])
		XCTAssertEqual(pomona.pads[0].drill, .mm(6.35))
		XCTAssertEqual(pomona.pads[0].size, Size(width: .mm(10.0), height: .mm(10.0)))
		XCTAssertEqual(pomona.pads[1].at, Pt(x: 0, y: .mm(5.0)))
		XCTAssertEqual(pomona.pads[1].drill, .mm(1.0))
		XCTAssertTrue(pomona.pads[0].figure.contains(pomona.pads[1].at))

		for component in [Component.nkkMN12, .nkkMN15] {
			let nkk = try XCTUnwrap(component.makeFootprint())
			XCTAssertEqual(nkk.pads.map(\.at), [
				Pt(x: 0, y: -.mm(4.7)), .zero, Pt(x: 0, y: .mm(4.7)),
			])
			XCTAssertTrue(nkk.pads.allSatisfy { $0.drill == .mm(1.6) })
		}

		let bourns = try XCTUnwrap(Component.bourns51.makeFootprint())
		XCTAssertEqual(bourns.pads.map(\.at), [
			Pt(x: -.mm(2.54), y: -.mm(7.5)),
			Pt(x: 0, y: -.mm(7.5)),
			Pt(x: .mm(2.54), y: -.mm(7.5)),
		])
		XCTAssertTrue(bourns.pads.allSatisfy { $0.drill == .mm(0.9) })
	}

	func testPomonaCompoundPadSyncsAndFormsOneCopperIsland() {
		var design = Design(board: Board(size: Size(width: .mm(30), height: .mm(30)), stack: .two))
		design.schematic.symbols = [
			Symbol(spec: .init(component: .pomona1581), reference: "J1", at: .zero),
		]
		let pin = design.schematic.symbols[0].placedPins[0].at
		design.schematic.wires = [
			Wire(start: pin, end: Pt(x: pin.x + .mm(2.54), y: pin.y)),
		]
		design.schematic.labels = [NetLabel(at: pin, text: "JACK")]
		design.board.footprints = [
			Footprint(spec: .init(component: .pomona1581), reference: "J1", at: Pt(x: .mm(15), y: .mm(15))),
		]

		let report = design.updateBoardFromSchematic()
		XCTAssertEqual(report.assigned, 1)
		XCTAssertEqual(Set(design.board.footprints[0].pads.compactMap(\.net)).count, 1)
		XCTAssertTrue(design.board.footprints[0].pads.allSatisfy { $0.net != nil })
		XCTAssertEqual(design.board.ratsnest(), [])
	}

	func testLibrarySpecsUsePartValuePackageAndReferencePrefix() throws {
		let symbol = Symbol(
			spec: .init(component: .oneN4148W),
			reference: "D1",
			at: .zero
		)
		XCTAssertEqual(symbol.kind, .diode)
		XCTAssertEqual(symbol.value, "1N4148W")
		XCTAssertEqual(symbol.pins.sorted(by: numericPinOrder).map(\.name), ["K", "A"])

		let footprint = Footprint(
			spec: .init(component: .ssi2162),
			reference: "U1",
			at: .zero
		)
		XCTAssertEqual(footprint.value, "SSI2162")
		XCTAssertEqual(footprint.pads.count, 10)
		XCTAssertEqual(Footprint.Spec(component: .bourns51).referencePrefix, "RV")
	}

	private func numericOrder(_ lhs: String, _ rhs: String) -> Bool {
		Int(lhs) ?? 0 < Int(rhs) ?? 0
	}

	private func numericPinOrder(_ lhs: Pin, _ rhs: Pin) -> Bool {
		numericOrder(lhs.number, rhs.number)
	}
}
