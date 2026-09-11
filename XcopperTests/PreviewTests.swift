import simd
import SwiftUI
import XCTest
@testable import Xcopper

final class PreviewTests: XCTestCase {

	private func board(_ stack: Stack = .classic) -> Board {
		Board(size: Size(width: 40 * .mm, height: 30 * .mm), stack: stack)
	}

	private func chip(at point: Point, flipped: Bool = false) -> Footprint {
		modifying(Footprint(spec: .init(kind: .chip, chip: .c0805), reference: "R1", at: point)) {
			$0.flipped = flipped
		}
	}

	func testALoopWoundLikeTheLayoutDrawsItFacesUp() {
		let square = Rect(origin: .zero, size: Size(width: 10 * .mm, height: 10 * .mm))

		XCTAssertEqual(square.corners.map { $0.v3(0.0) }.normal, V3(x: 0.0, y: 0.0, z: 1.0))
		XCTAssertEqual(
			square.corners.reversed().map { $0.v3(0.0) }.normal,
			V3(x: 0.0, y: 0.0, z: -1.0)
		)
	}

	func testACircleIsWoundTheSameWayAsARectangle() {
		let ring = circle(at: .zero, diameter: 4 * .mm).map { $0.v3(0.0) }

		XCTAssertEqual(ring.normal.z, 1.0, accuracy: 0.0001)
	}

	func testACurveIsCutAsFinelyAsItsSizeAsksFor() {
		XCTAssertEqual(Figure.round(.zero, 10 * .mm).polygon().count, 32)
		XCTAssertEqual(Figure.round(.zero, 6_350).polygon().count, 32)
		XCTAssertEqual(Figure.round(.zero, 500).polygon().count, 12)

		for diameter in [400, 1 * .mm, 2 * .mm, 6_350, 10 * .mm] {
			let sides = Double(Figure.round(.zero, diameter).polygon().count)
			XCTAssertLessThan(
				Double.mm(diameter) / 2.0 * (1.0 - cos(.pi / sides)),
				0.025,
				"\(Double.mm(diameter)) mm across"
			)
		}
		XCTAssertEqual(Figure.round(.zero, 25 * .mm).polygon().count, 32)
	}

	func testAStadiumSurroundsTheTraceItStandsFor() {
		let start = Point(x: 2 * .mm, y: 5 * .mm)
		let end = Point(x: 9 * .mm, y: 5 * .mm)
		let outline = stadium(from: start, to: end, width: 1 * .mm)
		let bounds = Rect.union(outline.map { Rect(origin: $0, size: .zero) })

		XCTAssertEqual(outline.map { $0.v3(0.0) }.normal.z, 1.0, accuracy: 0.0001)
		XCTAssertEqual(bounds?.minX, 1_500)
		XCTAssertEqual(bounds?.maxX, 9_500)
		XCTAssertEqual(bounds?.minY, 4_500)
		XCTAssertEqual(bounds?.maxY, 5_500)
	}

	func testASideFacesOutOfTheBoardOnEitherSurface() {
		let outline = Rect(origin: .zero, size: Size(width: 8 * .mm, height: 6 * .mm)).corners
		let top = Side(up: true, z: 0.0, layer: 0)
		let bottom = Side(up: false, z: -1.6, layer: 1)

		XCTAssertEqual(top.loop(outline).normal.z, 1.0, accuracy: 0.0001)
		XCTAssertEqual(bottom.loop(outline).normal.z, -1.0, accuracy: 0.0001)
		XCTAssertEqual(top.lift(2.0), 2.0)
		XCTAssertEqual(bottom.lift(2.0), -3.6)
	}

	func testAPrismShowsItsWallsOutwardsAndItsFarEndOnTheFarSide() {
		let outline = Rect(center: .zero, size: Size(width: 2 * .mm, height: 2 * .mm)).corners

		for (from, to) in [(0.0, 1.0), (-1.6, -2.6)] {
			var model = Model()
			model.add(prism: outline, from: from, to: to, shade: .part(Palette.moulding), level: 0)
			XCTAssertEqual(model.pieces.count, 5, "four walls and a cap")

			XCTAssertEqual(
				model.pieces.last?.normal.z ?? 0.0,
				to > from ? 1.0 : -1.0,
				accuracy: 0.0001
			)
			for wall in model.pieces.dropLast() {
				XCTAssertEqual(wall.normal.z, 0.0, accuracy: 0.0001)
				let corner = wall.loop[0]
				XCTAssertGreaterThan(
					wall.normal.dot(V3(x: corner.x, y: corner.y, z: 0.0)),
					0.0,
					"a wall of a prism looks away from its middle"
				)
			}
		}
	}

	func testABareBoardIsTwoMaskedFacesAnEdgeAndNothingElse() {
		let model = board().model(Finish().shape)
		let levels = Set(model.pieces.map(\.level))

		XCTAssertEqual(levels, [Side(up: true, z: 0, layer: 0).mask, Side(up: false, z: 0, layer: 1).mask, Side.core])
		XCTAssertEqual(model.pieces.count { $0.level == Side.core }, 4, "one wall per edge")
	}

	func testEveryDrillIsPunchedThroughBothFacesAndLinedWithABarrel() {
		var board = board()
		board.holes.append(Hole(at: Point(x: 10 * .mm, y: 10 * .mm), diameter: 3 * .mm))
		board.vias.append(Via(at: Point(x: 20 * .mm, y: 10 * .mm), net: nil))

		let model = board.model(Finish().shape)
		let faces = model.pieces.filter { abs($0.level) == 10 }

		XCTAssertEqual(faces.count, 2)
		for face in faces {
			XCTAssertEqual(face.holes.count, 2, "both drills read through the substrate")
		}
	}

	func testCopperGoesOnTheFaceItsLayerBelongsTo() {
		var board = board()
		board.traces.append(Trace(start: .zero, end: Point(x: 10 * .mm, y: 0), width: 300, layer: 0, net: nil))
		board.traces.append(Trace(start: .zero, end: Point(x: 10 * .mm, y: 0), width: 300, layer: 1, net: nil))

		let model = board.model(Finish().shape)

		XCTAssertEqual(model.pieces.count { $0.level == 20 }, 1)
		XCTAssertEqual(model.pieces.count { $0.level == -20 }, 1)
	}

	func testViaCopperAndBarrelsFollowBoardSizesInThePreview() {
		var board = board()
		board.vias = [Via(at: Point(x: 20 * .mm, y: 10 * .mm), net: nil)]
		for (drill, pad) in [(300, 600), (800, 1_400)] {
			board.rules.viaDrill = drill
			board.rules.viaPad = pad
			let model = board.model(Finish().shape)
			let copper = model.pieces.filter { abs($0.level) == 20 }
			XCTAssertEqual(copper.count, 2)
			for face in copper {
				let xs = face.loop.map(\.x)
				XCTAssertEqual((xs.max() ?? 0) - (xs.min() ?? 0), Double.mm(pad), accuracy: 0.0001)
			}
			let barrels = model.pieces.filter { $0.level == Side.core && $0.shade == .plating }
			let xs = barrels.flatMap { $0.loop.map(\.x) }
			XCTAssertEqual((xs.max() ?? 0) - (xs.min() ?? 0), Double.mm(drill), accuracy: 0.0001)
		}
	}

	func testAnInnerLayerHasNothingToShow() {
		var board = board(.digital)
		board.traces.append(Trace(start: .zero, end: Point(x: 10 * .mm, y: 0), width: 300, layer: 1, net: nil))

		let model = board.model(Finish().shape)

		XCTAssertEqual(model.pieces.count { abs($0.level) == 20 }, 0, "buried copper does not surface")
	}

	func testAFlippedPartStandsUnderTheBoard() {
		var board = board()
		board.footprints = [chip(at: Point(x: 10 * .mm, y: 10 * .mm), flipped: true)]

		let model = board.model(Finish().shape)

		XCTAssertGreaterThan(model.pieces.count { $0.level == -50 }, 0)
		XCTAssertEqual(model.pieces.count { $0.level == 50 }, 0)
		XCTAssertTrue(model.pieces.allSatisfy { piece in piece.loop.allSatisfy { $0.z <= 0.0 } })
	}

	func testTheBoardCarriesNoLegend() {
		var board = board()
		board.footprints = [chip(at: Point(x: 10 * .mm, y: 10 * .mm))]

		let model = board.model(Finish().shape)

		XCTAssertTrue(model.pieces.allSatisfy { piece in
			abs(piece.level) <= 25 || abs(piece.level) == 50
		})
	}

	func testWhatIsSwitchedOffIsNotBuilt() {
		var board = board()
		board.footprints = [chip(at: Point(x: 10 * .mm, y: 10 * .mm))]
		board.traces.append(Trace(start: .zero, end: Point(x: 10 * .mm, y: 0), width: 300, layer: 0, net: nil))

		let bare = board.model(modifying(Finish()) {
			$0.copper = false
			$0.components = false
		}.shape)

		XCTAssertTrue(bare.pieces.allSatisfy { abs($0.level) <= 10 })
	}

	func testAClearMaskLeavesEveryPieceOfCopperPlated() {
		var board = board()
		board.traces.append(Trace(start: .zero, end: Point(x: 10 * .mm, y: 0), width: 300, layer: 0, net: nil))
		board.vias.append(Via(at: Point(x: 20 * .mm, y: 10 * .mm), net: nil))
		board.footprints = [chip(at: Point(x: 10 * .mm, y: 10 * .mm))]

		let gold = Plating.gold.rgb
		let clear = modifying(Finish()) { $0.mask = .clear }
		let green = Finish()

		let copper = board.model(green.shape).pieces
			.filter { piece in (20 ... 25).contains(abs(piece.level)) }

		XCTAssertFalse(copper.isEmpty)
		XCTAssertTrue(copper.allSatisfy { $0.shade.rgb(clear) == gold })
		XCTAssertTrue(copper.contains { $0.shade.rgb(green) != gold }, "a trace under green is not")
	}

	private func area(of triangles: [V3]) -> Double {
		stride(from: 0, to: triangles.count, by: 3).reduce(0.0) { total, corner in
			let a = triangles[corner + 1] - triangles[corner]
			let b = triangles[corner + 2] - triangles[corner]
			return total + a.cross(b).length / 2.0
		}
	}

	private func assertFacing(_ triangles: [V3], _ facing: Double) {
		XCTAssertFalse(triangles.isEmpty)
		XCTAssertEqual(triangles.count % 3, 0)

		for corner in stride(from: 0, to: triangles.count, by: 3) {
			let a = triangles[corner + 1] - triangles[corner]
			let b = triangles[corner + 2] - triangles[corner]
			XCTAssertEqual(a.cross(b).normalized.z, facing, accuracy: 0.0001)
		}
	}

	private func drilled(_ diameter: µm) -> Double {
		area(of: circle(at: .zero, diameter: diameter))
	}

	private var square: [V3] {
		Rect(origin: .zero, size: Size(width: 20 * .mm, height: 20 * .mm))
			.corners.map { $0.v3(0.0) }
	}

	func testAFaceIsCutIntoTrianglesThatCoverIt() {
		let triangles = triangulate(square, holes: [], facing: V3(x: 0.0, y: 0.0, z: 1.0))

		XCTAssertEqual(triangles.count, 6, "a square is two triangles")
		XCTAssertEqual(area(of: triangles), 400.0, accuracy: 0.001)
		assertFacing(triangles, 1.0)
	}

	func testADrillIsCutRoundRatherThanCoveredOver() {
		let drill = circle(at: Point(x: 10 * .mm, y: 10 * .mm), diameter: 6 * .mm)
		let triangles = triangulate(
			square,
			holes: [drill.map { $0.v3(0.0) }],
			facing: V3(x: 0.0, y: 0.0, z: 1.0)
		)

		XCTAssertEqual(area(of: triangles), 400.0 - drilled(6 * .mm), accuracy: 0.01)
		assertFacing(triangles, 1.0)
	}

	func testEveryDrillIsCutRoundEvenWhereTheyCrowdTheFace() {
		let drills = (0 ..< 9).map { index -> [Point] in
			let across = (4 + 6 * (index % 3)) * .mm
			let down = (4 + 6 * (index / 3)) * .mm
			return circle(at: Point(x: across, y: down), diameter: 3 * .mm)
		}
		let triangles = triangulate(
			square,
			holes: drills.map { drill in drill.map { $0.v3(0.0) } },
			facing: V3(x: 0.0, y: 0.0, z: 1.0)
		)

		XCTAssertEqual(area(of: triangles), 400.0 - 9.0 * drilled(3 * .mm), accuracy: 0.02)
		assertFacing(triangles, 1.0)
	}

	func testTheUndersideOfTheBoardIsCutTheSameWayRound() {
		let side = Side(up: false, z: -1.6, layer: 1)
		let outline = side.loop(Rect(origin: .zero, size: Size(width: 20 * .mm, height: 20 * .mm)).corners)
		let drill = side.loop(circle(at: Point(x: 10 * .mm, y: 10 * .mm), diameter: 6 * .mm))

		let triangles = triangulate(outline, holes: [drill], facing: V3(x: 0.0, y: 0.0, z: -1.0))

		XCTAssertEqual(area(of: triangles), 400.0 - drilled(6 * .mm), accuracy: 0.01)
		XCTAssertTrue(triangles.allSatisfy { $0.z == -1.6 })
		assertFacing(triangles, -1.0)
	}

	private func board(_ width: µm, _ height: µm) -> [V3] {
		Rect(origin: .zero, size: Size(width: width, height: height))
			.corners.map { $0.v3(0.0) }
	}

	private func drills(_ places: [(µm, µm)], _ diameter: µm) -> [[V3]] {
		places.map { across, down in
			circle(at: Point(x: across, y: down), diameter: diameter)
				.map { $0.v3(0.0) }
		}
	}

	func testDrillsCutOpenToTheSameCornerDoNotCrossTheirSeams() {
		let face = board(160 * .mm, 100 * .mm)
		let punches = drills([(6 * .mm, 6 * .mm), (154 * .mm, 6 * .mm)], 500)

		let triangles = triangulate(face, holes: punches, facing: V3(x: 0.0, y: 0.0, z: 1.0))

		XCTAssertEqual(area(of: triangles), 16_000.0 - 2.0 * drilled(500), accuracy: 0.01)
		assertFacing(triangles, 1.0)
	}

	func testAFaceCrowdedWithDrillsIsStillCutToWhatItCovers() {
		var places: [(µm, µm)] = []
		for row in 0 ..< 2 {
			for pin in 0 ..< 20 {
				places.append((10 * .mm + pin * 2_540, 10 * .mm + row * 2_540))
			}
		}
		for via in 0 ..< 120 {
			places.append((8 * .mm + (via % 20) * 7_100, 30 * .mm + (via / 20) * 9_300))
		}
		let triangles = triangulate(
			board(160 * .mm, 100 * .mm),
			holes: drills(places, 500),
			facing: V3(x: 0.0, y: 0.0, z: 1.0)
		)

		XCTAssertEqual(
			area(of: triangles),
			16_000.0 - Double(places.count) * drilled(500),
			accuracy: 0.05
		)
		assertFacing(triangles, 1.0)
	}

	func testADrillTheFaceDoesNotHoldWholeLeavesItWhole() {
		let stray = circle(at: Point(x: 40 * .mm, y: 10 * .mm), diameter: 4 * .mm)
		let overhanging = circle(at: Point(x: 20 * .mm, y: 10 * .mm), diameter: 4 * .mm)

		for drill in [stray, overhanging] {
			let triangles = triangulate(
				square,
				holes: [drill.map { $0.v3(0.0) }],
				facing: V3(x: 0.0, y: 0.0, z: 1.0)
			)
			XCTAssertEqual(area(of: triangles), 400.0, accuracy: 0.001)
			assertFacing(triangles, 1.0)
		}
	}

	private func area(of loop: [Point]) -> Double {
		var sum = 0
		var previous = loop[loop.count - 1]

		for point in loop {
			sum += previous.x * point.y - point.x * previous.y
			previous = point
		}
		return Double(sum) / Double(2 * µm.mm * µm.mm)
	}

	func testADrillTakesBackTheCopperThatStoodOverIt() {
		let face = Rect(origin: .zero, size: Size(width: 20 * .mm, height: 20 * .mm)).corners
		let drill = circle(at: Point(x: 10 * .mm, y: 0), diameter: 6 * .mm)

		let pieces = punched(face, by: [drill])

		XCTAssertEqual(
			pieces.reduce(0.0) { total, piece in total + area(of: piece) },
			400.0 - drilled(6 * .mm) / 2.0,
			accuracy: 0.01
		)
		for piece in pieces {
			XCTAssertGreaterThan(area(of: piece), 0.0, "cut the way the layout draws it")
			XCTAssertFalse(holds(piece, [Point(x: 10 * .mm, y: 1 * .mm)]), "no copper over the hole")
		}
		XCTAssertTrue(pieces.contains { holds($0, [Point(x: 10 * .mm, y: 10 * .mm)]) }, "the rest stays")
	}

	func testCopperIsCutBackToEveryDrillReachingIntoItAtOnce() {
		let ring = Figure.round(.zero, 10 * .mm).polygon()
		let barrel = Figure.round(.zero, 6_350).polygon()
		let wire = Figure.round(Point(x: 0, y: 5 * .mm), 1 * .mm).polygon()

		let pieces = punched(ring, by: [barrel, wire])
		let covered = pieces.reduce(0.0) { total, piece in total + area(of: piece) }

		XCTAssertGreaterThan(covered, drilled(10 * .mm) - drilled(6_350) - drilled(1 * .mm))
		XCTAssertLessThan(covered, drilled(10 * .mm) - drilled(6_350) - drilled(1 * .mm) / 3.0)
		for piece in pieces {
			XCTAssertGreaterThan(area(of: piece), 0.0)
			XCTAssertFalse(holds(piece, [.zero]), "the barrel is not covered over")
			XCTAssertFalse(holds(piece, [Point(x: 0, y: 5 * .mm)]), "nor is the wire hole")
		}
	}

	func testADrillRightAcrossATraceLeavesCopperEitherSideOfIt() {
		let trace = Figure.segment(.zero, Point(x: 10 * .mm, y: 0), 300).polygon(arc: 2)
		let hole = circle(at: Point(x: 5 * .mm, y: 0), diameter: 1 * .mm)

		let pieces = punched(trace, by: [hole])

		XCTAssertTrue(pieces.contains { holds($0, [Point(x: 1 * .mm, y: 0)]) })
		XCTAssertTrue(pieces.contains { holds($0, [Point(x: 9 * .mm, y: 0)]) })
		XCTAssertFalse(pieces.contains { holds($0, [Point(x: 5 * .mm, y: 0)]) }, "the hole is open")
	}

	func testAMaskChangesWhatTheBoardIsPaintedInAndNotWhatItIsMadeOf() {
		let green = Finish()
		let black = modifying(Finish()) { $0.mask = .black }
		let thicker = modifying(Finish()) { $0.thickness = µm.thicknesses[2] }
		let bare = modifying(Finish()) { $0.copper = false }

		XCTAssertEqual(green.shape, black.shape)
		XCTAssertNotEqual(green.shape, thicker.shape, "a core is something it is made of")
		XCTAssertNotEqual(green.shape, bare.shape, "and so is copper it is not shown")

		XCTAssertNotEqual(Shade.mask.rgb(green), Shade.mask.rgb(black))
		XCTAssertNotEqual(Shade.coating.rgb(green), Shade.coating.rgb(black))
		XCTAssertEqual(Shade.solder.rgb(green), Shade.solder.rgb(black), "solder is solder")
	}

	func testTheModelIsGatheredIntoOneSurfacePerShade() {
		var board = board()
		board.traces = (0 ..< 4).map { index -> Trace in
			let down = (2 + 3 * index) * .mm
			return Trace(
				start: Point(x: 2 * .mm, y: Int(down)),
				end: Point(x: 12 * .mm, y: Int(down)),
				width: 300,
				layer: 0,
				net: nil
			)
		}
		board.footprints = [chip(at: Point(x: 20 * .mm, y: 20 * .mm))]

		let model = board.model(Finish().shape)
		let surfaces = model.surfaces

		XCTAssertEqual(surfaces.count, Set(model.pieces.map(\.shade)).count)
		XCTAssertEqual(Set(surfaces.map(\.shade)), Set(model.pieces.map(\.shade)))
		for surface in surfaces {
			XCTAssertEqual(surface.corners.count, surface.normals.count)
			XCTAssertEqual(surface.corners.count % 3, 0, "three corners to a triangle")
			XCTAssertFalse(surface.corners.isEmpty)
		}
	}

	func testEachLevelStandsClearOfTheOneUnderIt() {
		var board = board()
		board.traces.append(Trace(start: .zero, end: Point(x: 10 * .mm, y: 0), width: 300, layer: 0, net: nil))
		board.traces.append(Trace(start: .zero, end: Point(x: 10 * .mm, y: 0), width: 300, layer: 1, net: nil))

		let pieces = board.model(Finish().shape).pieces
		func lift(_ level: Int) -> Double {
			pieces.first { $0.level == level }?.lift.z ?? .nan
		}

		XCTAssertGreaterThan(lift(20), lift(10))
		XCTAssertGreaterThan(lift(10), 0.0)
		XCTAssertLessThan(lift(-20), lift(-10))
		XCTAssertLessThan(lift(-10), 0.0)
		XCTAssertLessThan(abs(lift(20)), 0.05)
	}

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

	func testTheEyeStandsWhereTheCameraIsAndLooksTheWayItIsTurned() {
		var camera = Camera(target: V3(x: 20.0, y: 15.0, z: 0.0), distance: 100.0)
		camera.aim(at: .top)
		let pose = camera.pose

		func axis(_ column: SIMD4<Float>) -> SIMD3<Float> {
			SIMD3(column.x, column.y, column.z)
		}

		XCTAssertEqual(pose.columns.3.x, 0.020, accuracy: 0.0001)
		XCTAssertEqual(pose.columns.3.y, 0.100, accuracy: 0.0001)
		XCTAssertEqual(pose.columns.3.z, 0.015, accuracy: 0.0001)

		XCTAssertEqual(axis(pose.columns.2).y, 1.0, accuracy: 0.0001)
		XCTAssertEqual(axis(pose.columns.0).x, 1.0, accuracy: 0.0001)
		XCTAssertEqual(axis(pose.columns.1).z, -1.0, accuracy: 0.0001)

		let handedness = simd_cross(axis(pose.columns.0), axis(pose.columns.1))
		XCTAssertEqual(handedness.y, axis(pose.columns.2).y, accuracy: 0.0001)
	}

	func testTurningTheBoardIntoASceneTurnsItsWindingRound() {
		let face = Rect(origin: .zero, size: Size(width: 10 * .mm, height: 10 * .mm))
			.corners.map { $0.v3(0.0) }
		XCTAssertEqual(face.normal, V3(x: 0.0, y: 0.0, z: 1.0), "out of the top copper")
		XCTAssertEqual(face.normal.turned, SIMD3<Float>(0.0, 1.0, 0.0), "up the scene")

		let turned = face.map(\.turned)
		let normal = simd_normalize(simd_cross(turned[1] - turned[0], turned[2] - turned[0]))
		XCTAssertEqual(normal.y, -1.0, accuracy: 0.0001)
	}

	func testFittingPutsTheWholeBoardInFrontOfTheEye() {
		var state = PreviewState()
		state.canvas = CGSize(width: 900.0, height: 700.0)
		state.frame(board())

		XCTAssertTrue(state.framed)
		XCTAssertEqual(state.camera.target.x, 20.0, accuracy: 0.001)
		XCTAssertEqual(state.camera.target.y, 15.0, accuracy: 0.001)
		XCTAssertEqual(state.camera.distance, state.reach, accuracy: 0.001)

		let camera = state.camera
		let vertical = tan(camera.fov / 2.0)
		let horizontal = vertical * Double(state.canvas.width / state.canvas.height)
		for corner in board().bounds.corners {
			let offset = corner.v3(0.0) - camera.eye
			let depth = offset.dot(camera.forward)

			XCTAssertGreaterThan(depth, Camera.near, "corner \(corner) is behind the eye")
			XCTAssertLessThanOrEqual(abs(offset.dot(camera.right)), depth * horizontal)
			XCTAssertLessThanOrEqual(abs(offset.dot(camera.up)), depth * vertical)
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
