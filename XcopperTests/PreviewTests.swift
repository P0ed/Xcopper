import simd
import SwiftUI
import XCTest
@testable import Xcopper

/// The 3D preview turns the board into flat faces, cuts those into triangles
/// and hands them to a renderer, which only works while every loop is wound the
/// way the layout draws it and every level keeps its place in the stack.
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

	func testACurveIsCutAsFinelyAsItsSizeAsksFor() {
		// The ring of a panel jack and the barrel through it read as round; a
		// via's barrel is not cut finer than anything could show
		XCTAssertEqual(Figure.round(.zero, .mm(10)).polygon().count, 32)
		XCTAssertEqual(Figure.round(.zero, .mm(6.35)).polygon().count, 32)
		XCTAssertEqual(Figure.round(.zero, .mm(0.5)).polygon().count, 12)

		// Up to the size copper comes in, no side of a curve stands more than a
		// hair off the curve itself
		for diameter in [0.4, 1.0, 2.0, 6.35, 10.0] {
			let sides = Double(Figure.round(.zero, .mm(diameter)).polygon().count)
			XCTAssertLessThan(
				diameter / 2.0 * (1.0 - cos(.pi / sides)),
				0.025,
				"\(diameter) mm across"
			)
		}
		// And nothing is cut finer than that, however wide it is
		XCTAssertEqual(Figure.round(.zero, .mm(25)).polygon().count, 32)
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
			model.add(prism: outline, from: from, to: to, shade: .part(Palette.moulding), level: 0)
			XCTAssertEqual(model.pieces.count, 5, "four walls and a cap")

			// The cap looks away from the board and no wall leans inwards
			XCTAssertEqual(
				model.pieces.last?.normal.z ?? 0.0,
				to > from ? 1.0 : -1.0,
				accuracy: 0.0001
			)
			for wall in model.pieces.dropLast() {
				XCTAssertEqual(wall.normal.z, 0.0, accuracy: 0.0001)
				// The prism stands on the middle, so a corner of a wall is the
				// way out of it
				let corner = wall.loop[0]
				XCTAssertGreaterThan(
					wall.normal.dot(V3(x: corner.x, y: corner.y, z: 0.0)),
					0.0,
					"a wall of a prism looks away from its middle"
				)
			}
		}
	}

	// MARK: the model

	func testABareBoardIsTwoMaskedFacesAnEdgeAndNothingElse() {
		let model = board().model(Finish().shape)
		let levels = Set(model.pieces.map(\.level))

		XCTAssertEqual(levels, [Side(up: true, z: 0, layer: 0).mask, Side(up: false, z: 0, layer: 1).mask, Side.core])
		XCTAssertEqual(model.pieces.count { $0.level == Side.core }, 4, "one wall per edge")
	}

	func testEveryDrillIsPunchedThroughBothFacesAndLinedWithABarrel() {
		var board = board()
		board.holes.append(Hole(at: Pt(x: .mm(10), y: .mm(10)), diameter: .mm(3)))
		board.vias.append(Via(at: Pt(x: .mm(20), y: .mm(10)), drill: .mm(0.5), pad: .mm(0.9), from: 0, to: 1, net: nil))

		let model = board.model(Finish().shape)
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

		let model = board.model(Finish().shape)

		XCTAssertEqual(model.pieces.count { $0.level == 20 }, 1)
		XCTAssertEqual(model.pieces.count { $0.level == -20 }, 1)
	}

	func testAnInnerLayerHasNothingToShow() {
		var board = board(.four)
		board.traces.append(Trace(start: .zero, end: Pt(x: .mm(10), y: 0), width: .mm(0.3), layer: 1, net: nil))

		let model = board.model(Finish().shape)

		XCTAssertEqual(model.pieces.count { abs($0.level) == 20 }, 0, "buried copper does not surface")
	}

	func testAFlippedPartStandsUnderTheBoard() {
		var board = board()
		board.footprints = [chip(at: Pt(x: .mm(10), y: .mm(10)), flipped: true)]

		let model = board.model(Finish().shape)

		XCTAssertGreaterThan(model.pieces.count { $0.level == -50 }, 0)
		XCTAssertEqual(model.pieces.count { $0.level == 50 }, 0)
		XCTAssertTrue(model.pieces.allSatisfy { piece in piece.loop.allSatisfy { $0.z <= 0.0 } })
	}

	func testTheBoardCarriesNoLegend() {
		var board = board()
		board.footprints = [chip(at: Pt(x: .mm(10), y: .mm(10)))]

		let model = board.model(Finish().shape)

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

		let bare = board.model(modifying(Finish()) {
			$0.copper = false
			$0.components = false
		}.shape)

		XCTAssertTrue(bare.pieces.allSatisfy { abs($0.level) <= 10 })
	}

	func testAClearMaskLeavesEveryPieceOfCopperPlated() {
		var board = board()
		board.traces.append(Trace(start: .zero, end: Pt(x: .mm(10), y: 0), width: .mm(0.3), layer: 0, net: nil))
		board.vias.append(Via(at: Pt(x: .mm(20), y: .mm(10)), drill: .mm(0.5), pad: .mm(0.9), from: 0, to: 1, net: nil))
		board.footprints = [chip(at: Pt(x: .mm(10), y: .mm(10)))]

		let gold = Plating.gold.rgb
		let clear = modifying(Finish()) { $0.mask = .clear }
		let green = Finish()

		// One board, since a mask changes what the copper is painted in and not
		// where any of it lies
		let copper = board.model(green.shape).pieces
			.filter { piece in (20 ... 25).contains(abs(piece.level)) }

		// Clear is the want of a mask rather than a colour of one: nothing is
		// covered, so the finish that plates the pads plates the rest as well
		XCTAssertFalse(copper.isEmpty)
		XCTAssertTrue(copper.allSatisfy { $0.shade.rgb(clear) == gold })
		XCTAssertTrue(copper.contains { $0.shade.rgb(green) != gold }, "a trace under green is not")
	}

	// MARK: triangles

	/// How much a face cut into triangles covers, which is the whole of what
	/// it stood for and no more
	private func area(of triangles: [V3]) -> Double {
		stride(from: 0, to: triangles.count, by: 3).reduce(0.0) { total, corner in
			let a = triangles[corner + 1] - triangles[corner]
			let b = triangles[corner + 2] - triangles[corner]
			return total + a.cross(b).length / 2.0
		}
	}

	/// Every triangle looks the way the face it was cut from does. One turned
	/// the other way about would be dropped by the renderer as a back face.
	private func assertFacing(_ triangles: [V3], _ facing: Double) {
		XCTAssertFalse(triangles.isEmpty)
		XCTAssertEqual(triangles.count % 3, 0)

		for corner in stride(from: 0, to: triangles.count, by: 3) {
			let a = triangles[corner + 1] - triangles[corner]
			let b = triangles[corner + 2] - triangles[corner]
			XCTAssertEqual(a.cross(b).normalized.z, facing, accuracy: 0.0001)
		}
	}

	/// How much a drill covers once it is drawn as the ring of straight sides
	/// the model builds it out of, which is a little under the circle it stands
	/// for
	private func drilled(_ diameter: Double) -> Double {
		let radius = diameter / 2.0
		let sides = Double(fineness(across: .mm(diameter)) * 4)
		return sides * radius * radius * sin(2.0 * .pi / sides) / 2.0
	}

	private var square: [V3] {
		Rect(origin: .zero, size: Size(width: .mm(20), height: .mm(20)))
			.corners.map { $0.v3(0.0) }
	}

	func testAFaceIsCutIntoTrianglesThatCoverIt() {
		let triangles = triangulate(square, holes: [], facing: V3(x: 0.0, y: 0.0, z: 1.0))

		XCTAssertEqual(triangles.count, 6, "a square is two triangles")
		XCTAssertEqual(area(of: triangles), 400.0, accuracy: 0.001)
		assertFacing(triangles, 1.0)
	}

	func testADrillIsCutRoundRatherThanCoveredOver() {
		let drill = circle(at: Pt(x: .mm(10), y: .mm(10)), diameter: .mm(6))
		let triangles = triangulate(
			square,
			holes: [drill.map { $0.v3(0.0) }],
			facing: V3(x: 0.0, y: 0.0, z: 1.0)
		)

		XCTAssertEqual(area(of: triangles), 400.0 - drilled(6.0), accuracy: 0.01)
		assertFacing(triangles, 1.0)
	}

	func testEveryDrillIsCutRoundEvenWhereTheyCrowdTheFace() {
		let drills = (0 ..< 9).map { index -> [Pt] in
			let across = Double(4 + 6 * (index % 3))
			let down = Double(4 + 6 * (index / 3))
			return circle(at: Pt(x: .mm(across), y: .mm(down)), diameter: .mm(3))
		}
		let triangles = triangulate(
			square,
			holes: drills.map { drill in drill.map { $0.v3(0.0) } },
			facing: V3(x: 0.0, y: 0.0, z: 1.0)
		)

		XCTAssertEqual(area(of: triangles), 400.0 - 9.0 * drilled(3.0), accuracy: 0.02)
		assertFacing(triangles, 1.0)
	}

	func testTheUndersideOfTheBoardIsCutTheSameWayRound() {
		let side = Side(up: false, z: -1.6, layer: 1)
		let outline = side.loop(Rect(origin: .zero, size: Size(width: .mm(20), height: .mm(20))).corners)
		let drill = side.loop(circle(at: Pt(x: .mm(10), y: .mm(10)), diameter: .mm(6)))

		let triangles = triangulate(outline, holes: [drill], facing: V3(x: 0.0, y: 0.0, z: -1.0))

		XCTAssertEqual(area(of: triangles), 400.0 - drilled(6.0), accuracy: 0.01)
		XCTAssertTrue(triangles.allSatisfy { $0.z == -1.6 })
		assertFacing(triangles, -1.0)
	}

	/// A board is not a square, and the drills on it line up in rows and
	/// columns rather than falling anywhere
	private func board(_ width: Double, _ height: Double) -> [V3] {
		Rect(origin: .zero, size: Size(width: .mm(width), height: .mm(height)))
			.corners.map { $0.v3(0.0) }
	}

	private func drills(_ places: [(Double, Double)], _ diameter: Double) -> [[V3]] {
		places.map { across, down in
			circle(at: Pt(x: .mm(across), y: .mm(down)), diameter: .mm(diameter))
				.map { $0.v3(0.0) }
		}
	}

	func testDrillsCutOpenToTheSameCornerDoNotCrossTheirSeams() {
		// Both of these reach the same corner of the face, so both are cut open
		// to it. A corner already cut to has a wedge of the face either side of
		// the seam it carries, and the second cut has to leave from the one its
		// own drill lies in: made from the other, the two seams fold the face
		// over itself and it comes back covering more than it stands for.
		let face = board(160.0, 100.0)
		let punches = drills([(6.0, 6.0), (154.0, 6.0)], 0.5)

		let triangles = triangulate(face, holes: punches, facing: V3(x: 0.0, y: 0.0, z: 1.0))

		XCTAssertEqual(area(of: triangles), 16_000.0 - 2.0 * drilled(0.5), accuracy: 0.01)
		assertFacing(triangles, 1.0)
	}

	func testAFaceCrowdedWithDrillsIsStillCutToWhatItCovers() {
		// Two headers' worth of pins on the 2.54 mm grid a board really uses,
		// and a field of vias besides: enough corners that the face files where
		// they stand rather than walking all of them for every cut and ear
		var places: [(Double, Double)] = []
		for row in 0 ..< 2 {
			for pin in 0 ..< 20 {
				places.append((10.0 + Double(pin) * 2.54, 10.0 + Double(row) * 2.54))
			}
		}
		for via in 0 ..< 120 {
			places.append((8.0 + Double(via % 20) * 7.1, 30.0 + Double(via / 20) * 9.3))
		}
		let triangles = triangulate(
			board(160.0, 100.0),
			holes: drills(places, 0.5),
			facing: V3(x: 0.0, y: 0.0, z: 1.0)
		)

		XCTAssertEqual(
			area(of: triangles),
			16_000.0 - Double(places.count) * drilled(0.5),
			accuracy: 0.05
		)
		assertFacing(triangles, 1.0)
	}

	func testADrillTheFaceDoesNotHoldWholeLeavesItWhole() {
		let stray = circle(at: Pt(x: .mm(40), y: .mm(10)), diameter: .mm(4))
		let overhanging = circle(at: Pt(x: .mm(20), y: .mm(10)), diameter: .mm(4))

		// Neither is a hole in the face: one is nowhere near it and the other
		// hangs over its edge, and cutting the face open to either would leave
		// it in pieces that overlap
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

	// MARK: punching

	/// How much a flat loop covers, in square millimeters, positive where it is
	/// wound the way the layout draws one
	private func area(of loop: [Pt]) -> Double {
		var sum = 0.0
		var previous = loop[loop.count - 1]

		for point in loop {
			sum += Double(previous.x).mm * Double(point.y).mm
				- Double(point.x).mm * Double(previous.y).mm
			previous = point
		}
		return sum / 2.0
	}

	/// Whether the triangles a face is cut into cover a point on the board,
	/// which is what asks a face whether it stands over a hole
	private func covers(_ piece: Piece, _ point: Pt) -> Bool {
		let triangles = triangulate(piece.loop, holes: piece.holes, facing: piece.normal)
		let at = point.v3(0.0)

		func turn(_ a: V3, _ b: V3) -> Double {
			(b.x - a.x) * (at.y - a.y) - (b.y - a.y) * (at.x - a.x)
		}
		return stride(from: 0, to: triangles.count, by: 3).contains { corner in
			let turns = [
				turn(triangles[corner], triangles[corner + 1]),
				turn(triangles[corner + 1], triangles[corner + 2]),
				turn(triangles[corner + 2], triangles[corner]),
			]
			return turns.allSatisfy { $0 >= 0.0 } || turns.allSatisfy { $0 <= 0.0 }
		}
	}

	/// The middle of a drill and four points well inside its rim, which is what
	/// a face that closes over it covers
	private func inside(_ drill: Figure) -> [Pt] {
		guard case let .round(center, diameter) = drill else { return [] }
		let reach = Int(diameter) / 3

		return [center] + [Pt(x: reach, y: 0), Pt(x: -reach, y: 0), Pt(x: 0, y: reach), Pt(x: 0, y: -reach)]
			.map { offset in center + offset }
	}

	func testADrillTakesBackTheCopperThatStoodOverIt() {
		let face = Rect(origin: .zero, size: Size(width: .mm(20), height: .mm(20))).corners
		// Sat on the edge of the face, so half of it is copper to take back and
		// half of it never was
		let drill = circle(at: Pt(x: .mm(10), y: 0), diameter: .mm(6))

		let pieces = punched(face, by: [drill])

		XCTAssertEqual(
			pieces.reduce(0.0) { total, piece in total + area(of: piece) },
			400.0 - drilled(6.0) / 2.0,
			accuracy: 0.01
		)
		for piece in pieces {
			XCTAssertGreaterThan(area(of: piece), 0.0, "cut the way the layout draws it")
			XCTAssertFalse(holds(piece, [Pt(x: .mm(10), y: .mm(1))]), "no copper over the hole")
		}
		XCTAssertTrue(pieces.contains { holds($0, [Pt(x: .mm(10), y: .mm(10))]) }, "the rest stays")
	}

	func testCopperIsCutBackToEveryDrillReachingIntoItAtOnce() {
		// The Pomona ring: its own barrel punched clean through the middle of
		// it and the wire hole beside it reaching over its edge
		let ring = Figure.round(.zero, .mm(10)).polygon()
		let barrel = Figure.round(.zero, .mm(6.35)).polygon()
		let wire = Figure.round(Pt(x: .mm(5), y: 0), .mm(1)).polygon()

		let pieces = punched(ring, by: [barrel, wire])
		let covered = pieces.reduce(0.0) { total, piece in total + area(of: piece) }

		XCTAssertGreaterThan(covered, drilled(10.0) - drilled(6.35) - drilled(1.0))
		XCTAssertLessThan(covered, drilled(10.0) - drilled(6.35) - drilled(1.0) / 3.0)
		for piece in pieces {
			XCTAssertGreaterThan(area(of: piece), 0.0)
			XCTAssertFalse(holds(piece, [.zero]), "the barrel is not covered over")
			XCTAssertFalse(holds(piece, [Pt(x: .mm(5), y: 0)]), "nor is the wire hole")
		}
	}

	func testADrillRightAcrossATraceLeavesCopperEitherSideOfIt() {
		let trace = Figure.segment(.zero, Pt(x: .mm(10), y: 0), .mm(0.3)).polygon(arc: 2)
		let hole = circle(at: Pt(x: .mm(5), y: 0), diameter: .mm(1))

		let pieces = punched(trace, by: [hole])

		XCTAssertTrue(pieces.contains { holds($0, [Pt(x: .mm(1), y: 0)]) })
		XCTAssertTrue(pieces.contains { holds($0, [Pt(x: .mm(9), y: 0)]) })
		XCTAssertFalse(pieces.contains { holds($0, [Pt(x: .mm(5), y: 0)]) }, "the hole is open")
	}

	func testNoCopperOnEitherFaceStandsOverAHole() {
		var board = board()
		board.footprints = [
			Footprint(spec: .init(component: .pomona1581), reference: "J1", at: Pt(x: .mm(20), y: .mm(15))),
		]
		// A route onto the wire hole, narrower than the drill it lands on, and
		// a mounting hole punched through the ring itself
		board.traces.append(Trace(
			start: Pt(x: .mm(25), y: .mm(25)),
			end: Pt(x: .mm(25), y: .mm(15)),
			width: .mm(0.8),
			layer: 0,
			net: nil
		))
		board.holes.append(Hole(at: Pt(x: .mm(16), y: .mm(15)), diameter: .mm(2)))

		let copper = board.model(Finish().shape).pieces
			.filter { piece in (20 ... 25).contains(abs(piece.level)) }

		XCTAssertFalse(copper.isEmpty)
		for drill in board.drills {
			for point in inside(drill) {
				XCTAssertFalse(
					copper.contains { piece in covers(piece, point) },
					"copper standing over \(drill)"
				)
			}
		}
		// And no more of it is taken back than the drills themselves: the ring
		// still stands everywhere they do not reach
		XCTAssertTrue(copper.contains { piece in covers(piece, Pt(x: .mm(20), y: .mm(19))) }, "the ring")
		XCTAssertTrue(copper.contains { piece in covers(piece, Pt(x: .mm(25), y: .mm(20))) }, "the trace")
	}

	// MARK: surfaces

	func testAMaskChangesWhatTheBoardIsPaintedInAndNotWhatItIsMadeOf() {
		let green = Finish()
		let black = modifying(Finish()) { $0.mask = .black }
		let thicker = modifying(Finish()) { $0.thickness = Nm.thicknesses[2] }
		let bare = modifying(Finish()) { $0.copper = false }

		// Nothing about the shape of the board follows from its colour, so a
		// mask picked in the sidebar leaves the model already built standing and
		// only asks for it to be painted again
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
			let down = Nm.mm(Double(2 + 3 * index))
			return Trace(
				start: Pt(x: .mm(2), y: Int(down)),
				end: Pt(x: .mm(12), y: Int(down)),
				width: .mm(0.3),
				layer: 0,
				net: nil
			)
		}
		board.footprints = [chip(at: Pt(x: .mm(20), y: .mm(20)))]

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
		board.traces.append(Trace(start: .zero, end: Pt(x: .mm(10), y: 0), width: .mm(0.3), layer: 0, net: nil))
		board.traces.append(Trace(start: .zero, end: Pt(x: .mm(10), y: 0), width: .mm(0.3), layer: 1, net: nil))

		let pieces = board.model(Finish().shape).pieces
		func lift(_ level: Int) -> Double {
			pieces.first { $0.level == level }?.lift.z ?? .nan
		}

		// The copper reads over the mask on the face it is on, which on the
		// underside means below it
		XCTAssertGreaterThan(lift(20), lift(10))
		XCTAssertGreaterThan(lift(10), 0.0)
		XCTAssertLessThan(lift(-20), lift(-10))
		XCTAssertLessThan(lift(-10), 0.0)
		// And no lift is anything the eye or the fab would call a gap
		XCTAssertLessThan(abs(lift(20)), 0.05)
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

		let model = board.model(Finish().shape)

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

	func testTheEyeStandsWhereTheCameraIsAndLooksTheWayItIsTurned() {
		var camera = Camera(target: V3(x: 20.0, y: 15.0, z: 0.0), distance: 100.0)
		camera.aim(at: .top)
		let pose = camera.pose

		func axis(_ column: SIMD4<Float>) -> SIMD3<Float> {
			SIMD3(column.x, column.y, column.z)
		}

		// A hundred millimeters over the middle of the board is a tenth of a
		// metre up the scene's own Y
		XCTAssertEqual(pose.columns.3.x, 0.020, accuracy: 0.0001)
		XCTAssertEqual(pose.columns.3.y, 0.100, accuracy: 0.0001)
		XCTAssertEqual(pose.columns.3.z, 0.015, accuracy: 0.0001)

		// A camera looks along its own negative Z, which from up there is
		// straight down at the board, and board Y still runs down the screen
		XCTAssertEqual(axis(pose.columns.2).y, 1.0, accuracy: 0.0001)
		XCTAssertEqual(axis(pose.columns.0).x, 1.0, accuracy: 0.0001)
		XCTAssertEqual(axis(pose.columns.1).z, -1.0, accuracy: 0.0001)

		// Right crossed into up is back, or the view comes out mirrored
		let handedness = simd_cross(axis(pose.columns.0), axis(pose.columns.1))
		XCTAssertEqual(handedness.y, axis(pose.columns.2).y, accuracy: 0.0001)
	}

	func testTurningTheBoardIntoASceneTurnsItsWindingRound() {
		let face = Rect(origin: .zero, size: Size(width: .mm(10), height: .mm(10)))
			.corners.map { $0.v3(0.0) }
		XCTAssertEqual(face.normal, V3(x: 0.0, y: 0.0, z: 1.0), "out of the top copper")
		XCTAssertEqual(face.normal.turned, SIMD3<Float>(0.0, 1.0, 0.0), "up the scene")

		// The same corners in the same order wind the other way about that
		// normal once the space has been turned over, which is why a face is
		// handed to the renderer backwards
		let turned = face.map(\.turned)
		let normal = simd_normalize(simd_cross(turned[1] - turned[0], turned[2] - turned[0]))
		XCTAssertEqual(normal.y, -1.0, accuracy: 0.0001)
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
