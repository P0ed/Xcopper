import XCTest
@testable import Xcopper

final class FabricationTests: XCTestCase {

	private func design(_ stack: Stack = .digital) -> Design {
		Design(board: Board(size: Size(width: .mm(50), height: .mm(40)), stack: stack))
	}

	private func file(_ design: Design, _ suffix: String) -> String {
		design.fabrication(named: "Board")
			.first { $0.name.hasSuffix(suffix) }
			.map(\.text) ?? ""
	}

	private func lines(_ text: String) -> [String] {
		text.split(separator: "\n").map(String.init)
	}

	private func smd(_ name: String, at: Pt, size: Size) -> Pad {
		Pad(at: at, size: size, shape: .rect, drill: 0, layer: 0, name: name, net: nil)
	}

	private func footprint(_ reference: String, at: Pt, pads: [Pad], flipped: Bool = false) -> Footprint {
		Footprint(
			reference: reference,
			value: "",
			at: at,
			rotation: .r0,
			flipped: flipped,
			pads: pads,
			body: Rect(center: .zero, size: Size(width: .mm(2), height: .mm(1)))
		)
	}

	func testTheOutlineFileIsWrittenWholeWithYCountingUpFromTheBottom() {
		XCTAssertEqual(
			file(design(), "Edge_Cuts.gbr"),
			"""
			G04 Xcopper*
			%TF.GenerationSoftware,Xcopper*%
			%TF.FileFunction,Profile,NP*%
			%TF.FilePolarity,Positive*%
			%TF.Part,Single*%
			%FSLAX46Y46*%
			%MOMM*%
			%ADD10C,0.100000*%
			G01*
			%LPD*%
			D10*
			X0Y40000000D02*
			X50000000Y40000000D01*
			X50000000Y0D01*
			X0Y0D01*
			X0Y40000000D01*
			M02*

			"""
		)
	}

	func testATraceBecomesADrawWithACircularApertureOfItsWidth() {
		var design = design()
		design.board.traces = [
			Trace(
				start: Pt(x: .mm(10), y: .mm(10)),
				end: Pt(x: .mm(20), y: .mm(10)),
				width: .mm(0.25),
				layer: 0,
				net: nil
			),
		]
		let text = file(design, "F_Cu.gbr")

		XCTAssertTrue(text.contains("%ADD10C,0.250000*%"))
		XCTAssertTrue(text.contains("X10000000Y30000000D02*"))
		XCTAssertTrue(text.contains("X20000000Y30000000D01*"))
	}

	func testIdenticalFiguresShareOneApertureAndOneSelection() {
		var design = design()
		design.board.traces = (0 ..< 3).map { index in
			Trace(
				start: Pt(x: .mm(5), y: index * .mm(2)),
				end: Pt(x: .mm(15), y: index * .mm(2)),
				width: .mm(0.25),
				layer: 0,
				net: nil
			)
		}
		let text = file(design, "F_Cu.gbr")

		XCTAssertEqual(lines(text).count { $0.hasPrefix("%ADD") }, 1)
		XCTAssertEqual(lines(text).count { $0 == "D10*" }, 1)
		XCTAssertEqual(lines(text).count { $0.hasSuffix("D01*") }, 3)
	}

	func testARectangularPadFlashesARectangleTheSizeOfThePad() {
		var design = design()
		design.board.footprints = [
			footprint(
				"R1",
				at: Pt(x: .mm(10), y: .mm(10)),
				pads: [smd("1", at: .zero, size: Size(width: .mm(1.2), height: .mm(0.8)))]
			),
		]
		let text = file(design, "F_Cu.gbr")

		XCTAssertTrue(text.contains("%ADD10R,1.200000X0.800000*%"))
		XCTAssertTrue(text.contains("X10000000Y30000000D03*"))
	}

	func testAQuarterTurnedPadFlashesTheSwappedRectangle() {
		var design = design()
		design.board.footprints = [
			modifying(
				footprint(
					"R1",
					at: Pt(x: .mm(10), y: .mm(10)),
					pads: [smd("1", at: .zero, size: Size(width: .mm(1.2), height: .mm(0.8)))]
				)
			) { $0.rotation = .r90 },
		]
		XCTAssertTrue(file(design, "F_Cu.gbr").contains("%ADD10R,0.800000X1.200000*%"))
	}

	func testAPlanePoursTheBoardThenClearsItBackAroundForeignCopper() {
		var design = design()
		design.board.vias = [
			Via(at: Pt(x: .mm(10), y: .mm(10)), drill: .mm(0.5), pad: .mm(0.9), from: 0, to: 3, net: 1),
		]
		let steps = lines(file(design, "In1_Cu.gbr")).filter {
			$0 == "G36*" || $0 == "G37*" || $0 == "%LPC*%" || $0 == "%LPD*%"
		}
		XCTAssertEqual(steps, ["%LPD*%", "G36*", "G37*", "%LPC*%", "%LPD*%"])
	}

	func testThePlaneRegionStopsOneClearanceShortOfTheBoardEdge() {
		var design = design()
		let inset = Int(design.board.rules.clearance)
		let text = file(design, "In1_Cu.gbr")

		XCTAssertTrue(text.contains("X\(inset)Y\(Int.mm(40) - inset)D02*"))
		XCTAssertTrue(text.contains("X\(Int.mm(50) - inset)Y\(inset)D01*"))
	}

	func testCopperOnThePlanesOwnNetIsNotClearedAwayFromIt() {
		func knockouts(net: Net.ID?) -> Int {
			var design = design()
				design.board.vias = [
				Via(at: Pt(x: .mm(10), y: .mm(10)), drill: .mm(0.5), pad: .mm(0.9), from: 0, to: 3, net: net),
			]
			let all = lines(file(design, "In1_Cu.gbr"))
			guard
				let start = all.firstIndex(of: "%LPC*%"),
				let end = all.lastIndex(of: "%LPD*%"), start < end
			else { return 0 }
			return all[start ..< end].count { $0.hasSuffix("D03*") }
		}
		XCTAssertEqual(knockouts(net: 1), 1)
		XCTAssertEqual(knockouts(net: 0), 0)
	}

	func testKnockoutsAreGrownByTheClearanceRule() {
		var design = design()
		design.board.vias = [
			Via(at: Pt(x: .mm(10), y: .mm(10)), drill: .mm(0.5), pad: .mm(0.9), from: 0, to: 3, net: 1),
		]
		XCTAssertTrue(file(design, "In1_Cu.gbr").contains("%ADD10C,1.560000*%"))
	}

	func testCopperCarriesTheNetItBelongsToAndDropsTheAttributeWhenItEnds() {
		var design = design()
		design.board.traces = [
			Trace(start: Pt(x: .mm(5), y: .mm(5)), end: Pt(x: .mm(9), y: .mm(5)), width: .mm(0.25), layer: 0, net: 0),
			Trace(start: Pt(x: .mm(5), y: .mm(9)), end: Pt(x: .mm(9), y: .mm(9)), width: .mm(0.25), layer: 0, net: nil),
		]
		let attributes = lines(file(design, "F_Cu.gbr")).filter {
			$0.hasPrefix("%TO") || $0 == "%TD*%"
		}
		XCTAssertEqual(attributes, ["%TO.N,GND*%", "%TD*%"])
	}

	func testANetNameKeepsTheCharactersAnAttributeMayNotCarry() {
		var design = design()
		design.nets.append(Net(id: 9, name: "A,B*C"))
		design.board.traces = [
			Trace(start: Pt(x: .mm(5), y: .mm(5)), end: Pt(x: .mm(9), y: .mm(5)), width: .mm(0.25), layer: 0, net: 9),
		]
		XCTAssertTrue(file(design, "F_Cu.gbr").contains("%TO.N,A_B_C*%"))
	}

	func testTheMaskOpensOverEveryPadGrownByTheMaskExpansion() {
		var design = design()
		design.board.footprints = [
			footprint(
				"R1",
				at: Pt(x: .mm(10), y: .mm(10)),
				pads: [smd("1", at: .zero, size: Size(width: .mm(1), height: .mm(1)))]
			),
		]
		let text = file(design, "F_Mask.gbr")

		XCTAssertTrue(text.contains("%TF.FilePolarity,Negative*%"))
		XCTAssertTrue(text.contains("%ADD10R,1.100000X1.100000*%"))
	}

	func testAThroughPadOpensTheMaskOnBothFacesAndTakesNoPaste() {
		var design = design()
		design.board.footprints = [
			footprint(
				"J1",
				at: Pt(x: .mm(10), y: .mm(10)),
				pads: [
					Pad(
						at: .zero,
						size: Size(width: .mm(1.6), height: .mm(1.6)),
						shape: .oval,
						drill: .mm(0.8),
						layer: 0,
						name: "1",
						net: nil
					),
				]
			),
		]
		XCTAssertTrue(file(design, "F_Mask.gbr").contains("D03*"))
		XCTAssertTrue(file(design, "B_Mask.gbr").contains("D03*"))
		XCTAssertFalse(file(design, "F_Paste.gbr").contains("D03*"))
		XCTAssertFalse(file(design, "B_Paste.gbr").contains("D03*"))
	}

	func testPasteOpensOverSurfaceMountPadsAtTheirBareSize() {
		var design = design()
		design.board.footprints = [
			footprint(
				"R1",
				at: Pt(x: .mm(10), y: .mm(10)),
				pads: [smd("1", at: .zero, size: Size(width: .mm(1), height: .mm(1)))]
			),
		]
		XCTAssertTrue(file(design, "F_Paste.gbr").contains("%ADD10R,1.000000X1.000000*%"))
		XCTAssertFalse(file(design, "B_Paste.gbr").contains("D03*"))
	}

	func testAFlippedPartTakesItsCopperMaskAndPasteToTheBottomFace() {
		var design = design()
		design.board.footprints = [
			footprint(
				"R1",
				at: Pt(x: .mm(10), y: .mm(10)),
				pads: [smd("1", at: .zero, size: Size(width: .mm(1), height: .mm(1)))],
				flipped: true
			),
		]
		for face in ["Cu", "Mask", "Paste"] {
			XCTAssertFalse(file(design, "F_\(face).gbr").contains("D03*"), face)
			XCTAssertTrue(file(design, "B_\(face).gbr").contains("D03*"), face)
		}
	}

	func testPlatedHolesAreGroupedIntoOneToolPerDiameterSmallestFirst() {
		var design = design()
		design.board.vias = [
			Via(at: Pt(x: .mm(10), y: .mm(10)), drill: .mm(0.8), pad: .mm(1.2), from: 0, to: 3, net: nil),
			Via(at: Pt(x: .mm(20), y: .mm(10)), drill: .mm(0.5), pad: .mm(0.9), from: 0, to: 3, net: nil),
			Via(at: Pt(x: .mm(30), y: .mm(10)), drill: .mm(0.5), pad: .mm(0.9), from: 0, to: 3, net: nil),
		]
		let text = file(design, "PTH.drl")

		XCTAssertTrue(text.contains("; #@! TF.FileFunction,Plated,1,4,PTH"))
		XCTAssertTrue(text.contains("T1C0.500"))
		XCTAssertTrue(text.contains("T2C0.800"))
		XCTAssertEqual(lines(text).count { $0.hasPrefix("X") }, 3)

		let order = lines(text).filter { $0.hasPrefix("T") || $0.hasPrefix("X") }
		XCTAssertEqual(
			order,
			[
				"T1C0.500", "T2C0.800",
				"T1", "X20.0000Y30.0000", "X30.0000Y30.0000",
				"T2", "X10.0000Y30.0000",
				"T0",
			]
		)
	}

	func testThroughPadsDrillPlatedAndMountingHolesDrillBare() {
		var design = design()
		design.board.holes = [Hole(at: Pt(x: .mm(5), y: .mm(5)), diameter: .mm(3.2))]
		design.board.footprints = [
			footprint(
				"J1",
				at: Pt(x: .mm(10), y: .mm(10)),
				pads: [
					Pad(
						at: .zero,
						size: Size(width: .mm(1.6), height: .mm(1.6)),
						shape: .oval,
						drill: .mm(0.9),
						layer: 0,
						name: "1",
						net: nil
					),
				]
			),
		]
		XCTAssertTrue(file(design, "PTH.drl").contains("T1C0.900"))
		XCTAssertFalse(file(design, "PTH.drl").contains("3.200"))

		let bare = file(design, "NPTH.drl")
		XCTAssertTrue(bare.contains("; #@! TF.FileFunction,NonPlated,1,4,NPTH"))
		XCTAssertTrue(bare.contains("T1C3.200"))
		XCTAssertEqual(lines(bare).count { $0.hasPrefix("X") }, 1)
	}

	func testAnEmptyDrillProgramIsStillAValidOne() {
		XCTAssertEqual(
			file(design(), "NPTH.drl"),
			"""
			M48
			;DRILL file {Xcopper}
			;FORMAT={-:-/ absolute / metric / decimal}
			; #@! TF.FileFunction,NonPlated,1,4,NPTH
			; #@! TF.FilePolarity,Positive
			FMAT,2
			METRIC
			%
			G90
			G05
			T0
			M30

			"""
		)
	}

	func testTheSetCoversEveryCopperLayerOfTheStack() {
		XCTAssertEqual(
			design(.classic).fabrication(named: "Board").map(\.name),
			[
				"Board-F_Cu.gbr", "Board-B_Cu.gbr",
				"Board-F_Mask.gbr", "Board-B_Mask.gbr",
				"Board-F_Paste.gbr", "Board-B_Paste.gbr",
				"Board-Edge_Cuts.gbr",
				"Board-PTH.drl", "Board-NPTH.drl",
			]
		)
		XCTAssertEqual(
			design(.analog).fabrication(named: "Board").map(\.name).prefix(6),
			[
				"Board-F_Cu.gbr", "Board-In1_Cu.gbr", "Board-In2_Cu.gbr",
				"Board-In3_Cu.gbr", "Board-In4_Cu.gbr", "Board-B_Cu.gbr",
			]
		)
	}

	func testEveryCopperFileNamesItsPlaceInTheStack() {
		let functions = design(.digital).fabrication(named: "Board")
			.filter { $0.name.hasSuffix("_Cu.gbr") }
			.compactMap { file in
				lines(file.text).first { $0.hasPrefix("%TF.FileFunction") }
			}
		XCTAssertEqual(
			functions,
			[
				"%TF.FileFunction,Copper,L1,Top*%",
				"%TF.FileFunction,Copper,L2,Inr*%",
				"%TF.FileFunction,Copper,L3,Inr*%",
				"%TF.FileFunction,Copper,L4,Bot*%",
			]
		)
	}

	func testEveryFileOpensWithTheFormatItIsWrittenIn() {
		for file in design(.analog).fabrication(named: "Board") where file.name.hasSuffix(".gbr") {
			XCTAssertTrue(file.text.contains("%FSLAX46Y46*%"), file.name)
			XCTAssertTrue(file.text.contains("%MOMM*%"), file.name)
			XCTAssertTrue(file.text.hasSuffix("M02*\n"), file.name)
		}
	}

	func testTheFileStemIsCutDownToSomethingASystemWillTake() {
		XCTAssertEqual(Fabrication.stem("Amp/rev 2"), "Amp_rev 2")
		XCTAssertEqual(Fabrication.stem("  "), "Board")
		XCTAssertEqual(Fabrication.stem("Untitled"), "Untitled")
	}

	func testTheSetLandsInAFolderOnDisk() throws {
		let directory = URL(fileURLWithPath: NSTemporaryDirectory())
			.appending(path: "Xcopper-\(UUID().uuidString)")
		defer { try? FileManager.default.removeItem(at: directory) }

		let files = design(.classic).fabrication(named: "Board")
		try Fabrication.write(files, to: directory)

		for file in files {
			let url = directory.appending(path: file.name)
			XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), file.text)
		}
	}
}
