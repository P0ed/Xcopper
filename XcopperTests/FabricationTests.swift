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

	private func smd(_ name: String, at: Point, size: Size) -> Pad {
		Pad(at: at, size: size, shape: .rect, drill: 0, layer: 0, name: name, net: nil)
	}

	private func part(
		_ reference: String,
		_ value: String,
		_ spec: Footprint.Spec,
		at: Point = .zero,
		rotation: Rotation = .r0,
		flipped: Bool = false
	) -> Footprint {
		modifying(Footprint(spec: spec, reference: reference, at: at)) { part in
			part.value = value
			part.rotation = rotation
			part.flipped = flipped
		}
	}

	private func footprint(_ reference: String, at: Point, pads: [Pad], flipped: Bool = false) -> Footprint {
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
			file(design(), ".GKO"),
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
				start: Point(x: .mm(10), y: .mm(10)),
				end: Point(x: .mm(20), y: .mm(10)),
				width: .mm(0.25),
				layer: 0,
				net: nil
			),
		]
		let text = file(design, ".GTL")

		XCTAssertTrue(text.contains("%ADD10C,0.250000*%"))
		XCTAssertTrue(text.contains("X10000000Y30000000D02*"))
		XCTAssertTrue(text.contains("X20000000Y30000000D01*"))
	}

	func testIdenticalFiguresShareOneApertureAndOneSelection() {
		var design = design()
		design.board.traces = (0 ..< 3).map { index in
			Trace(
				start: Point(x: .mm(5), y: index * .mm(2)),
				end: Point(x: .mm(15), y: index * .mm(2)),
				width: .mm(0.25),
				layer: 0,
				net: nil
			)
		}
		let text = file(design, ".GTL")

		XCTAssertEqual(lines(text).count { $0.hasPrefix("%ADD") }, 1)
		XCTAssertEqual(lines(text).count { $0 == "D10*" }, 1)
		XCTAssertEqual(lines(text).count { $0.hasSuffix("D01*") }, 3)
	}

	func testARectangularPadFlashesARectangleTheSizeOfThePad() {
		var design = design()
		design.board.footprints = [
			footprint(
				"R1",
				at: Point(x: .mm(10), y: .mm(10)),
				pads: [smd("1", at: .zero, size: Size(width: .mm(1.2), height: .mm(0.8)))]
			),
		]
		let text = file(design, ".GTL")

		XCTAssertTrue(text.contains("%ADD10R,1.200000X0.800000*%"))
		XCTAssertTrue(text.contains("X10000000Y30000000D03*"))
	}

	func testAQuarterTurnedPadFlashesTheSwappedRectangle() {
		var design = design()
		design.board.footprints = [
			modifying(
				footprint(
					"R1",
					at: Point(x: .mm(10), y: .mm(10)),
					pads: [smd("1", at: .zero, size: Size(width: .mm(1.2), height: .mm(0.8)))]
				)
			) { $0.rotation = .r90 },
		]
		XCTAssertTrue(file(design, ".GTL").contains("%ADD10R,0.800000X1.200000*%"))
	}

	func testAPlanePoursTheBoardThenClearsItBackAroundForeignCopper() {
		var design = design()
		design.board.vias = [
			Via(at: Point(x: .mm(10), y: .mm(10)), drill: .mm(0.5), pad: .mm(0.9), from: 0, to: 3, net: 1),
		]
		let steps = lines(file(design, ".G1")).filter {
			$0 == "G36*" || $0 == "G37*" || $0 == "%LPC*%" || $0 == "%LPD*%"
		}
		XCTAssertEqual(steps, ["%LPD*%", "G36*", "G37*", "%LPC*%", "%LPD*%"])
	}

	func testThePlaneRegionStopsOneClearanceShortOfTheBoardEdge() {
		let design = design()
		let inset = Int(design.board.rules.clearance)
		let text = file(design, ".G1")

		XCTAssertTrue(text.contains("X\(inset)Y\(Int.mm(40) - inset)D02*"))
		XCTAssertTrue(text.contains("X\(Int.mm(50) - inset)Y\(inset)D01*"))
	}

	func testCopperOnThePlanesOwnNetIsNotClearedAwayFromIt() {
		func knockouts(net: Net.ID?) -> Int {
			var design = design()
				design.board.vias = [
				Via(at: Point(x: .mm(10), y: .mm(10)), drill: .mm(0.5), pad: .mm(0.9), from: 0, to: 3, net: net),
			]
			let all = lines(file(design, ".G1"))
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
		design.board.rules.clearance = .mm(0.33)
		design.board.vias = [
			Via(at: Point(x: .mm(10), y: .mm(10)), drill: .mm(0.5), pad: .mm(0.9), from: 0, to: 3, net: 1),
		]
		XCTAssertTrue(file(design, ".G1").contains("%ADD10C,1.560000*%"))
	}

	func testCopperCarriesTheNetItBelongsToAndDropsTheAttributeWhenItEnds() {
		var design = design()
		design.board.traces = [
			Trace(start: Point(x: .mm(5), y: .mm(5)), end: Point(x: .mm(9), y: .mm(5)), width: .mm(0.25), layer: 0, net: 0),
			Trace(start: Point(x: .mm(5), y: .mm(9)), end: Point(x: .mm(9), y: .mm(9)), width: .mm(0.25), layer: 0, net: nil),
		]
		let attributes = lines(file(design, ".GTL")).filter {
			$0.hasPrefix("%TO") || $0 == "%TD*%"
		}
		XCTAssertEqual(attributes, ["%TO.N,GND*%", "%TD*%"])
	}

	func testANetNameKeepsTheCharactersAnAttributeMayNotCarry() {
		var design = design()
		design.nets.append(Net(id: 9, name: "A,B*C"))
		design.board.traces = [
			Trace(start: Point(x: .mm(5), y: .mm(5)), end: Point(x: .mm(9), y: .mm(5)), width: .mm(0.25), layer: 0, net: 9),
		]
		XCTAssertTrue(file(design, ".GTL").contains("%TO.N,A_B_C*%"))
	}

	func testTheMaskOpensOverEveryPadGrownByTheMaskExpansion() {
		var design = design()
		design.board.footprints = [
			footprint(
				"R1",
				at: Point(x: .mm(10), y: .mm(10)),
				pads: [smd("1", at: .zero, size: Size(width: .mm(1), height: .mm(1)))]
			),
		]
		let text = file(design, ".GTS")

		XCTAssertTrue(text.contains("%TF.FilePolarity,Negative*%"))
		XCTAssertTrue(text.contains("%ADD10R,1.100000X1.100000*%"))
	}

	func testAThroughPadOpensTheMaskOnBothFacesAndTakesNoPaste() {
		var design = design()
		design.board.footprints = [
			footprint(
				"J1",
				at: Point(x: .mm(10), y: .mm(10)),
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
		XCTAssertTrue(file(design, ".GTS").contains("D03*"))
		XCTAssertTrue(file(design, ".GBS").contains("D03*"))
		XCTAssertFalse(file(design, ".GTP").contains("D03*"))
		XCTAssertFalse(file(design, ".GBP").contains("D03*"))
	}

	func testPasteOpensOverSurfaceMountPadsAtTheirBareSize() {
		var design = design()
		design.board.footprints = [
			footprint(
				"R1",
				at: Point(x: .mm(10), y: .mm(10)),
				pads: [smd("1", at: .zero, size: Size(width: .mm(1), height: .mm(1)))]
			),
		]
		XCTAssertTrue(file(design, ".GTP").contains("%ADD10R,1.000000X1.000000*%"))
		XCTAssertFalse(file(design, ".GBP").contains("D03*"))
	}

	func testAFlippedPartTakesItsCopperMaskAndPasteToTheBottomFace() {
		var design = design()
		design.board.footprints = [
			footprint(
				"R1",
				at: Point(x: .mm(10), y: .mm(10)),
				pads: [smd("1", at: .zero, size: Size(width: .mm(1), height: .mm(1)))],
				flipped: true
			),
		]
		for (top, bottom) in [(".GTL", ".GBL"), (".GTS", ".GBS"), (".GTP", ".GBP")] {
			XCTAssertFalse(file(design, top).contains("D03*"), top)
			XCTAssertTrue(file(design, bottom).contains("D03*"), bottom)
		}
	}

	func testPlatedHolesAreGroupedIntoOneToolPerDiameterSmallestFirst() {
		var design = design()
		design.board.vias = [
			Via(at: Point(x: .mm(10), y: .mm(10)), drill: .mm(0.8), pad: .mm(1.2), from: 0, to: 3, net: nil),
			Via(at: Point(x: .mm(20), y: .mm(10)), drill: .mm(0.5), pad: .mm(0.9), from: 0, to: 3, net: nil),
			Via(at: Point(x: .mm(30), y: .mm(10)), drill: .mm(0.5), pad: .mm(0.9), from: 0, to: 3, net: nil),
		]
		let text = file(design, "-PTH.DRL")

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
		design.board.holes = [Hole(at: Point(x: .mm(5), y: .mm(5)), diameter: .mm(3.2))]
		design.board.footprints = [
			footprint(
				"J1",
				at: Point(x: .mm(10), y: .mm(10)),
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
		XCTAssertTrue(file(design, "-PTH.DRL").contains("T1C0.900"))
		XCTAssertFalse(file(design, "-PTH.DRL").contains("3.200"))

		let bare = file(design, "-NPTH.DRL")
		XCTAssertTrue(bare.contains("; #@! TF.FileFunction,NonPlated,1,4,NPTH"))
		XCTAssertTrue(bare.contains("T1C3.200"))
		XCTAssertEqual(lines(bare).count { $0.hasPrefix("X") }, 1)
	}

	func testAnEmptyDrillProgramIsStillAValidOne() {
		XCTAssertEqual(
			file(design(), "-NPTH.DRL"),
			"""
			M48
			;DRILL file {Xcopper}
			;FORMAT={-:-/ absolute / metric / decimal}
			; #@! TF.FileFunction,NonPlated,1,4,NPTH
			; #@! TF.FilePolarity,Positive
			;TYPE=NON_PLATED
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
				"Board.GTL", "Board.GBL",
				"Board.GTS", "Board.GBS",
				"Board.GTP", "Board.GBP",
				"Board.GKO",
				"Board-PTH.DRL", "Board-NPTH.DRL",
				"Board-BOM.csv", "Board-CPL.csv",
			]
		)
		XCTAssertEqual(
			design(.analog).fabrication(named: "Board").map(\.name).prefix(6),
			["Board.GTL", "Board.G1", "Board.G2", "Board.G3", "Board.G4", "Board.GBL"]
		)
	}

	func testEveryCopperFileNamesItsPlaceInTheStack() {
		let functions = design(.digital).fabrication(named: "Board")
			.filter { file in [".GTL", ".G1", ".G2", ".GBL"].contains(where: file.name.hasSuffix) }
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
		for file in design(.analog).fabrication(named: "Board")
		where !file.name.hasSuffix(".DRL") && !file.name.hasSuffix(".csv") {
			XCTAssertTrue(file.text.contains("%FSLAX46Y46*%"), file.name)
			XCTAssertTrue(file.text.contains("%MOMM*%"), file.name)
			XCTAssertTrue(file.text.hasSuffix("M02*\n"), file.name)
		}
	}

	func testTheBillGathersThePartsThatShareAValueAndAPackage() {
		var design = design()
		design.board.footprints = [
			part("R1", "10k", .init(chip: .c0805, device: .resistor)),
			part("R10", "10k", .init(chip: .c0805, device: .resistor)),
			part("R2", "10k", .init(chip: .c0805, device: .resistor)),
			part("C1", "100n", .init(chip: .c0805, device: .capacitor)),
			part("U1", "AD823", .init(kind: .soic, pins: 8)),
		]
		XCTAssertEqual(
			lines(file(design, "-BOM.csv")),
			[
				"Comment,Designator,Footprint,Quantity",
				"100n,C1,Chip 0805,1",
				"10k,\"R1,R2,R10\",Chip 0805,3",
				"AD823,U1,SOIC-8,1",
			]
		)
	}

	func testAPartWithNothingWrittenOnItFallsBackToWhatItIs() {
		var design = design()
		design.board.footprints = [
			part("U1", "", .init(component: .ad823)),
			part("R1", "  ", .init(chip: .c0603, device: .resistor)),
		]
		XCTAssertEqual(
			lines(file(design, "-BOM.csv")).dropFirst(),
			["Resistor,R1,Chip 0603,1", "AD823,U1,SOIC-8,1"]
		)
	}

	func testAPartLeftOutOfTheBillIsNeitherBoughtNorPlaced() {
		var design = design()
		design.board.footprints = [
			part("R1", "10k", .init(chip: .c0805, device: .resistor)),
			modifying(part("J1", "Test point", .init(chip: .c0805, device: .resistor))) {
				$0.inBOM = false
			},
		]
		XCTAssertEqual(lines(file(design, "-BOM.csv")), ["Comment,Designator,Footprint,Quantity", "10k,R1,Chip 0805,1"])
		XCTAssertFalse(file(design, "-CPL.csv").contains("J1"))
	}

	func testThePlacementIsMeasuredFromTheCornerTheGerbersCountFrom() {
		var design = design()
		design.board.footprints = [
			part("R1", "10k", .init(chip: .c0805, device: .resistor), at: Point(x: .mm(10), y: .mm(10))),
		]
		XCTAssertEqual(
			lines(file(design, "-CPL.csv")),
			["Designator,Mid X,Mid Y,Layer,Rotation", "R1,10.0000mm,30.0000mm,top,0"]
		)
	}

	func testPlacementTurnsCounterClockwiseAsSeenFromTheSideThePartStandsOn() {
		func placed(_ rotation: Rotation, flipped: Bool = false) -> String {
			var design = design()
			design.board.footprints = [
				part("U1", "AD823", .init(kind: .soic, pins: 8), rotation: rotation, flipped: flipped),
			]
			return lines(file(design, "-CPL.csv"))[1]
		}
		XCTAssertEqual(placed(.r0), "U1,0.0000mm,40.0000mm,top,0")
		XCTAssertEqual(placed(.r90), "U1,0.0000mm,40.0000mm,top,270")
		XCTAssertEqual(placed(.r180), "U1,0.0000mm,40.0000mm,top,180")
		XCTAssertEqual(placed(.r270), "U1,0.0000mm,40.0000mm,top,90")
		XCTAssertEqual(placed(.r0, flipped: true), "U1,0.0000mm,40.0000mm,bottom,0")
		XCTAssertEqual(placed(.r90, flipped: true), "U1,0.0000mm,40.0000mm,bottom,90")
		XCTAssertEqual(placed(.r270, flipped: true), "U1,0.0000mm,40.0000mm,bottom,270")
	}

	func testAPartFromADocumentWrittenBeforeTheBillIsBought() throws {
		var design = design()
		design.board.footprints = [part("R1", "10k", .init(chip: .c0805, device: .resistor))]
		let json = try XCTUnwrap(String(data: Document(design: design).encoded(), encoding: .utf8))
		XCTAssertTrue(json.contains("\"inBOM\""))

		let older = json.split(separator: "\n", omittingEmptySubsequences: false)
			.filter { !$0.contains("\"inBOM\"") }
			.joined(separator: "\n")
		XCTAssertTrue(try Document.decode(Data(older.utf8)).board.footprints[0].inBOM)
	}

	func testAnEmptyBoardStillWritesTheHeadingsTheUploaderLooksFor() {
		XCTAssertEqual(file(design(), "-BOM.csv"), "Comment,Designator,Footprint,Quantity\n")
		XCTAssertEqual(file(design(), "-CPL.csv"), "Designator,Mid X,Mid Y,Layer,Rotation\n")
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
