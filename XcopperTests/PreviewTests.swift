import SwiftUI
import XCTest
@testable import Xcopper

/// The 3D preview turns the board into flat polygons and paints them back to
/// front, which only works while every loop is wound the way the layout draws
/// it and every level stays in its place in the stack.
final class PreviewTests: XCTestCase {

	private func board(_ stack: Stack = .two) -> Board {
		Board(size: Size(width: .mm(40), height: .mm(30)), stack: stack)
	}

	private func chip(at point: Pt, flipped: Bool = false) -> Footprint {
		modifying(Footprint(spec: .init(kind: .chip, chip: .c0805), reference: "R1", at: point)) {
			$0.flipped = flipped
		}
	}

	// MARK: winding

	func testALoopWoundLikeTheLayoutDrawsItFacesUp() {
		let square = Rect(origin: .zero, size: Size(width: .mm(10), height: .mm(10)))

		XCTAssertEqual(square.corners.map { $0.v3(0.0) }.normal, V3(x: 0.0, y: 0.0, z: 1.0))
		XCTAssertEqual(
			square.corners.reversed().map { $0.v3(0.0) }.normal,
			V3(x: 0.0, y: 0.0, z: -1.0)
		)
	}

	func testACircleIsWoundTheSameWayAsARectangle() {
		let ring = circle(at: .zero, diameter: .mm(4)).map { $0.v3(0.0) }

		XCTAssertEqual(ring.normal.z, 1.0, accuracy: 0.0001)
	}

	func testAStadiumSurroundsTheTraceItStandsFor() {
		let start = Pt(x: .mm(2), y: .mm(5))
		let end = Pt(x: .mm(9), y: .mm(5))
		let outline = stadium(from: start, to: end, width: .mm(1))
		let bounds = Rect.union(outline.map { Rect(origin: $0, size: .zero) })

		XCTAssertEqual(outline.map { $0.v3(0.0) }.normal.z, 1.0, accuracy: 0.0001)
		XCTAssertEqual(bounds?.minX, .mm(1.5))
		XCTAssertEqual(bounds?.maxX, .mm(9.5))
		XCTAssertEqual(bounds?.minY, .mm(4.5))
		XCTAssertEqual(bounds?.maxY, .mm(5.5))
	}

	func testASideFacesOutOfTheBoardOnEitherSurface() {
		let outline = Rect(origin: .zero, size: Size(width: .mm(8), height: .mm(6))).corners
		let top = Side(up: true, z: 0.0, layer: 0)
		let bottom = Side(up: false, z: -1.6, layer: 1)

		XCTAssertEqual(top.loop(outline).normal.z, 1.0, accuracy: 0.0001)
		XCTAssertEqual(bottom.loop(outline).normal.z, -1.0, accuracy: 0.0001)
		XCTAssertEqual(top.lift(2.0), 2.0)
		XCTAssertEqual(bottom.lift(2.0), -3.6)
	}

	func testAPrismShowsItsWallsOutwardsAndItsFarEndOnTheFarSide() {
		let outline = Rect(center: .zero, size: Size(width: .mm(2), height: .mm(2))).corners

		for (from, to) in [(0.0, 1.0), (-1.6, -2.6)] {
			var model = Model()
			model.add(prism: outline, from: from, to: to, color: Palette.moulding, level: 0)
			XCTAssertEqual(model.pieces.count, 5, "four walls and a cap")

			let normals = model.pieces.map(\.normal)
			// The cap looks away from the board and no wall leans inwards
			XCTAssertEqual(normals.last?.z ?? 0.0, to > from ? 1.0 : -1.0, accuracy: 0.0001)
			for normal in normals.dropLast() {
				XCTAssertEqual(normal.z, 0.0, accuracy: 0.0001)
				let outward = model.pieces[normals.firstIndex(of: normal)!].at
				XCTAssertGreaterThan(
					normal.dot(V3(x: outward.x, y: outward.y, z: 0.0)),
					0.0,
					"a wall of a prism looks away from its middle"
				)
			}
		}
	}

	// MARK: the model

	func testABareBoardIsTwoMaskedFacesAnEdgeAndNothingElse() {
		let model = board().model(finish: Finish())
		let levels = Set(model.pieces.map(\.level))

		XCTAssertEqual(levels, [Side(up: true, z: 0, layer: 0).mask, Side(up: false, z: 0, layer: 1).mask, Side.core])
		XCTAssertEqual(model.pieces.count { $0.level == Side.core }, 4, "one wall per edge")
	}

	func testEveryDrillIsPunchedThroughBothFacesAndLinedWithABarrel() {
		var board = board()
		board.holes.append(Hole(at: Pt(x: .mm(10), y: .mm(10)), diameter: .mm(3)))
		board.vias.append(Via(at: Pt(x: .mm(20), y: .mm(10)), drill: .mm(0.5), pad: .mm(0.9), from: 0, to: 1, net: nil))

		let model = board.model(finish: Finish())
		let faces = model.pieces.filter { abs($0.level) == 10 }

		XCTAssertEqual(faces.count, 2)
		for face in faces {
			XCTAssertEqual(face.holes.count, 2, "both drills read through the substrate")
		}
	}

	func testCopperGoesOnTheFaceItsLayerBelongsTo() {
		var board = board()
		board.traces.append(Trace(start: .zero, end: Pt(x: .mm(10), y: 0), width: .mm(0.3), layer: 0, net: nil))
		board.traces.append(Trace(start: .zero, end: Pt(x: .mm(10), y: 0), width: .mm(0.3), layer: 1, net: nil))

		let model = board.model(finish: Finish())

		XCTAssertEqual(model.pieces.count { $0.level == 20 }, 1)
		XCTAssertEqual(model.pieces.count { $0.level == -20 }, 1)
	}

	func testAnInnerLayerHasNothingToShow() {
		var board = board(.four)
		board.traces.append(Trace(start: .zero, end: Pt(x: .mm(10), y: 0), width: .mm(0.3), layer: 1, net: nil))

		let model = board.model(finish: Finish())

		XCTAssertEqual(model.pieces.count { abs($0.level) == 20 }, 0, "buried copper does not surface")
	}

	func testAFlippedPartStandsUnderTheBoard() {
		var board = board()
		board.footprints = [chip(at: Pt(x: .mm(10), y: .mm(10)), flipped: true)]

		let model = board.model(finish: Finish())

		XCTAssertGreaterThan(model.pieces.count { $0.level == -50 }, 0)
		XCTAssertEqual(model.pieces.count { $0.level == 50 }, 0)
		XCTAssertTrue(model.pieces.allSatisfy { $0.at.z <= 0.0 })
	}

	func testTheBoardCarriesNoLegend() {
		var board = board()
		board.footprints = [chip(at: Pt(x: .mm(10), y: .mm(10)))]

		let model = board.model(finish: Finish())

		// The fabrication set has no silkscreen in it, so neither has the
		// preview: nothing sits between the pads and the part standing on them
		XCTAssertTrue(model.pieces.allSatisfy { piece in
			abs(piece.level) <= 25 || abs(piece.level) == 50
		})
	}

	func testWhatIsSwitchedOffIsNotBuilt() {
		var board = board()
		board.footprints = [chip(at: Pt(x: .mm(10), y: .mm(10)))]
		board.traces.append(Trace(start: .zero, end: Pt(x: .mm(10), y: 0), width: .mm(0.3), layer: 0, net: nil))

		let bare = board.model(finish: modifying(Finish()) {
			$0.copper = false
			$0.components = false
		})

		XCTAssertTrue(bare.pieces.allSatisfy { abs($0.level) <= 10 })
	}

	func testAClearMaskLeavesEveryPieceOfCopperPlated() {
		var board = board()
		board.traces.append(Trace(start: .zero, end: Pt(x: .mm(10), y: 0), width: .mm(0.3), layer: 0, net: nil))
		board.vias.append(Via(at: Pt(x: .mm(20), y: .mm(10)), drill: .mm(0.5), pad: .mm(0.9), from: 0, to: 1, net: nil))
		board.footprints = [chip(at: Pt(x: .mm(10), y: .mm(10)))]

		let gold = Plating.gold.rgb
		let clear = board.model(finish: modifying(Finish()) { $0.mask = .clear })
		let green = board.model(finish: Finish())

		func copper(of model: Model) -> [Piece] {
			model.pieces.filter { piece in (20 ... 25).contains(abs(piece.level)) }
		}

		// Clear is the want of a mask rather than a colour of one: nothing is
		// covered, so the finish that plates the pads plates the rest as well
		XCTAssertFalse(copper(of: clear).isEmpty)
		XCTAssertTrue(copper(of: clear).allSatisfy { $0.color == gold })
		XCTAssertTrue(copper(of: green).contains { $0.color != gold }, "a trace under green is not")
	}

	// MARK: packages

	func testAPackageIsReadOffTheLandPatternWhenTheLibraryDoesNotKnowThePart() {
		let chip = Footprint(spec: .init(kind: .chip, chip: .c0805), reference: "R1", at: .zero)
		let dip = Footprint(spec: .init(kind: .dip, pins: 8), reference: "U1", at: .zero)
		let header = Footprint(spec: .init(kind: .header, pins: 4, rows: 1), reference: "J1", at: .zero)
		let soic = Footprint(spec: .init(kind: .soic, pins: 8), reference: "U2", at: .zero)

		XCTAssertTrue(chip.package.leads, "a chip is held up on its terminations")
		XCTAssertFalse(chip.package.posts)
		XCTAssertFalse(dip.package.posts, "a dip's leads are bent under it, not up through it")
		XCTAssertTrue(header.package.posts, "a header carries pins through its moulding")
		XCTAssertFalse(header.package.leads)
		XCTAssertGreaterThan(soic.package.height, chip.package.height)
	}

	func testASurfaceMountLegIsThinnerThanTheLandItIsSolderedTo() throws {
		let soic = Footprint(spec: .init(kind: .soic, pins: 8), reference: "U1", at: .zero)
		let pad = try XCTUnwrap(soic.placedPads.first)

		let land = pad.figure.bounds
		let leg = pad.leg.bounds

		XCTAssertLessThan(leg.size.height, land.size.height, "the solder fillets either side")
		XCTAssertLessThan(leg.size.width, land.size.width)
		XCTAssertEqual(leg.center, land.center, "the leg sits in the middle of its land")
	}

	func testAPartTheBoardOnlyCarriesThePadsOfStandsNowhereOnIt() {
		var board = board()
		board.footprints = [
			Footprint(spec: .init(component: .pomona1581), reference: "J1", at: Pt(x: .mm(20), y: .mm(15))),
		]

		let model = board.model(finish: Finish())

		XCTAssertFalse(board.footprints[0].package.stands, "a panel jack is held by the panel")
		XCTAssertEqual(board.standing(on: false), 0.0)
		// The ring and the barrel through it are the board's; nothing of the
		// jack itself is raised over either face
		XCTAssertEqual(model.pieces.count { abs($0.level) == 50 }, 0)
	}

	func testTheLibraryOverridesALandPatternThatWouldReadWrong() {
		let led = modifying(Footprint(spec: .init(kind: .chip, component: .hlmpWL02), reference: "D1", at: .zero)) {
			XCTAssertEqual($0.value, Component.hlmpWL02.name)
		}

		guard case let .dome(diameter) = led.package.shell else {
			return XCTFail("a 5 mm lamp is a lens, not the header its two holes suggest")
		}
		XCTAssertEqual(diameter, .mm(5.0))
		XCTAssertEqual(led.package.height, .mm(8.6))
	}

	// MARK: the camera

	func testLookingStraightDownReadsTheSameWayRoundAsTheLayout() {
		var camera = Camera()
		camera.aim(at: .top)

		XCTAssertEqual(camera.forward.z, -1.0, accuracy: 0.0001, "looking down")
		XCTAssertEqual(camera.right.x, 1.0, accuracy: 0.0001, "board X to the right")
		XCTAssertEqual(camera.up.y, -1.0, accuracy: 0.0001, "board Y down the screen")
		XCTAssertTrue(camera.overTop)

		camera.aim(at: .bottom)
		XCTAssertFalse(camera.overTop)
	}

	func testTheEyeStaysTheSetDistanceFromWhatItLooksAt() {
		for stand in Standpoint.allCases {
			var camera = Camera(target: V3(x: 20.0, y: 15.0, z: 0.0), distance: 90.0)
			camera.aim(at: stand)
			XCTAssertEqual((camera.eye - camera.target).length, 90.0, accuracy: 0.001)
		}
	}

	func testAPointInFrontOfTheEyeLandsWhereTheCameraIsPointed() {
		var camera = Camera(target: V3(x: 20.0, y: 15.0, z: 0.0), distance: 100.0)
		camera.aim(at: .top)
		let projector = Projector(camera: camera, size: CGSize(width: 800.0, height: 600.0))

		let middle = projector.project(camera.target)
		XCTAssertEqual(middle.x, 400.0, accuracy: 0.001)
		XCTAssertEqual(middle.y, 300.0, accuracy: 0.001)

		// Further along board Y is further down the screen, as on the layout
		XCTAssertGreaterThan(
			projector.project(camera.target + V3(x: 0.0, y: 5.0, z: 0.0)).y,
			middle.y
		)
		XCTAssertGreaterThan(
			projector.project(camera.target + V3(x: 5.0, y: 0.0, z: 0.0)).x,
			middle.x
		)
	}

	func testTheNearPlaneCutsAFaceRatherThanLosingIt() {
		let straddling = [
			V3(x: -1.0, y: 0.0, z: -1.0),
			V3(x: 1.0, y: 0.0, z: -1.0),
			V3(x: 1.0, y: 0.0, z: 4.0),
			V3(x: -1.0, y: 0.0, z: 4.0),
		]

		let clipped = clippedToNear(straddling)
		XCTAssertEqual(clipped.count, 4)
		XCTAssertTrue(clipped.allSatisfy { $0.z >= Projector.near - 0.0001 })
		XCTAssertTrue(clippedToNear(straddling.map { V3(x: $0.x, y: $0.y, z: -5.0) }).isEmpty)
	}

	func testOnlyTheFaceTurnedTowardsTheEyeIsDrawn() {
		var camera = Camera(target: .zero, distance: 50.0)
		camera.aim(at: .top)
		let projector = Projector(camera: camera, size: CGSize(width: 800.0, height: 600.0))

		XCTAssertTrue(projector.faces(V3(x: 0.0, y: 0.0, z: 1.0), at: .zero))
		XCTAssertFalse(projector.faces(V3(x: 0.0, y: 0.0, z: -1.0), at: .zero))
	}

	// MARK: framing

	func testFittingPutsTheWholeBoardInFrontOfTheEye() {
		var state = PreviewState()
		state.canvas = CGSize(width: 900.0, height: 700.0)
		state.frame(board())

		XCTAssertTrue(state.framed)
		XCTAssertEqual(state.camera.target.x, 20.0, accuracy: 0.001)
		XCTAssertEqual(state.camera.target.y, 15.0, accuracy: 0.001)
		XCTAssertEqual(state.camera.distance, state.reach, accuracy: 0.001)

		let projector = Projector(camera: state.camera, size: state.canvas)
		for corner in board().bounds.corners {
			let point = projector.project(corner.v3(0.0))
			XCTAssertTrue(
				CGRect(origin: .zero, size: state.canvas).contains(point),
				"corner \(corner) landed at \(point)"
			)
		}
	}

	func testZoomingReadsTheSameWayAsItDoesOnAFlatCanvas() {
		var state = PreviewState()
		state.canvas = CGSize(width: 900.0, height: 700.0)
		state.frame(board())

		XCTAssertEqual(state.magnification, 4.0, accuracy: 0.001, "framed is the neutral zoom")

		state.magnification = 8.0
		XCTAssertEqual(state.camera.distance, state.reach / 2.0, accuracy: 0.001)
		XCTAssertEqual(state.magnification, 8.0, accuracy: 0.001)
	}

	func testTheEyeWillNotClimbInsideTheBoard() {
		var camera = Camera(distance: 100.0)
		camera.zoom(by: 1_000.0, reach: 100.0)

		XCTAssertGreaterThan(camera.distance, 0.0)
		XCTAssertEqual(camera.distance, 100.0 / 24.0, accuracy: 0.001)
	}

	func testTurningTheBoardOverStaysWithinTheTravelOfTheHinge() {
		var camera = Camera()
		camera.orbit(by: CGSize(width: 0.0, height: 10_000.0))
		XCTAssertEqual(camera.elevation, .pi / 2.0, accuracy: 0.0001)

		camera.orbit(by: CGSize(width: 0.0, height: -20_000.0))
		XCTAssertEqual(camera.elevation, -.pi / 2.0, accuracy: 0.0001)
	}
}
