import XCTest
@testable import Xcopper

final class CheckTests: XCTestCase {

	private func design(_ stack: Stack = .classic) -> Design {
		Design(board: Board(size: Size(width: 50 * .mm, height: 40 * .mm), stack: stack))
	}

	private func at(_ x: µm, _ y: µm) -> Point { Point(x: x, y: y) }

	private func trace(
		_ from: Point,
		_ to: Point,
		net: Net.ID?,
		layer: Int = 0,
		width: µm = 300
	) -> Trace {
		Trace(start: from, end: to, width: width, layer: layer, net: net)
	}

	private func part(
		_ reference: String,
		at: Point,
		net: Net.ID?,
		pad: µm = 1_600,
		drill: µm = 800
	) -> Footprint {
		Footprint(
			reference: reference,
			value: "",
			at: at,
			rotation: .r0,
			flipped: false,
			pads: [
				Pad(
					at: .zero,
					size: Size(width: Int(pad), height: Int(pad)),
					shape: .oval,
					drill: drill,
					layer: 0,
					name: "1",
					net: net
				),
			],
			body: Rect(center: .zero, size: Size(width: Int(pad), height: Int(pad)))
		)
	}

	func testTwoCirclesAreMeasuredBetweenTheirRimsRatherThanTheirCentres() {
		XCTAssertEqual(
			gap(.round(at(10 * .mm, 10 * .mm), 2 * .mm), .round(at(20 * .mm, 10 * .mm), 4 * .mm)),
			Double(7 * .mm),
			accuracy: 1.0
		)
	}

	func testCopperThatOverlapsLeavesNoGapAtAll() {
		XCTAssertEqual(gap(.round(at(10 * .mm, 10 * .mm), 2 * .mm), .round(at(10_500, 10 * .mm), 2 * .mm)), 0.0)
	}

	func testTwoTracksCrossingLeaveNoGapEvenWhereNeitherEndIsNearTheOther() {
		XCTAssertEqual(
			gap(
				.segment(at(5 * .mm, 10 * .mm), at(15 * .mm, 10 * .mm), 300),
				.segment(at(10 * .mm, 5 * .mm), at(10 * .mm, 15 * .mm), 300)
			),
			0.0
		)
	}

	func testASquarePadIsMeasuredFromItsEdgeAndNotItsCorner() {
		XCTAssertEqual(
			gap(
				.rect(Rect(center: at(10 * .mm, 10 * .mm), size: Size(width: 2 * .mm, height: 2 * .mm))),
				.round(at(13 * .mm, 10 * .mm), 1 * .mm)
			),
			Double(1_500),
			accuracy: 1.0
		)
	}

	func testAPadDrawnWithNoSizeAtAllHoldsNothingAndShortsNothing() {
		XCTAssertEqual(
			gap(.rect(Rect(center: at(10 * .mm, 10 * .mm), size: .zero)), .round(at(20 * .mm, 10 * .mm), 2 * .mm)),
			Double(9 * .mm),
			accuracy: 1.0
		)
	}

	func testCopperOfTwoNetsCrossingIsReportedAsAShortWhereItCrosses() {
		var design = design()
		design.board.traces = [
			trace(at(5 * .mm, 10 * .mm), at(15 * .mm, 10 * .mm), net: 0),
			trace(at(10 * .mm, 5 * .mm), at(10 * .mm, 15 * .mm), net: 1),
		]

		let violations = design.check()
		XCTAssertEqual(violations.map(\.kind), [.short])
		XCTAssertEqual(violations[0].text, "GND meets VCC")
		XCTAssertEqual(violations[0].at, at(10 * .mm, 10 * .mm))
		XCTAssertEqual(violations[0].layer, 0)
	}

	func testAShortNamesBothPiecesOfCopperSoAClickPicksThemUp() {
		var design = design()
		design.board.traces = [
			trace(at(5 * .mm, 10 * .mm), at(15 * .mm, 10 * .mm), net: 0),
			trace(at(10 * .mm, 5 * .mm), at(10 * .mm, 15 * .mm), net: 1),
		]

		XCTAssertEqual(design.check().first?.refs, [.trace(0), .trace(1)])
	}

	func testCopperOfOneNetMayTouchItself() {
		var design = design()
		design.board.traces = [
			trace(at(5 * .mm, 10 * .mm), at(15 * .mm, 10 * .mm), net: 0),
			trace(at(10 * .mm, 5 * .mm), at(10 * .mm, 15 * .mm), net: 0),
		]

		XCTAssertEqual(design.check(), [])
	}

	func testCopperTheDesignHasNotNamedIsNotJudgedAgainstAnything() {
		var design = design()
		design.board.traces = [
			trace(at(5 * .mm, 10 * .mm), at(15 * .mm, 10 * .mm), net: nil),
			trace(at(10 * .mm, 5 * .mm), at(10 * .mm, 15 * .mm), net: 1),
		]

		XCTAssertEqual(design.check(), [])
	}

	func testCopperOnTwoLayersMayCrossFreely() {
		var design = design()
		design.board.traces = [
			trace(at(5 * .mm, 10 * .mm), at(15 * .mm, 10 * .mm), net: 0, layer: 0),
			trace(at(10 * .mm, 5 * .mm), at(10 * .mm, 15 * .mm), net: 1, layer: 1),
		]

		XCTAssertEqual(design.check(), [])
	}

	func testCopperRunningTooCloseToAnotherNetIsReportedWithTheGapItLeaves() {
		var design = design()
		design.board.traces = [
			trace(at(5 * .mm, 10 * .mm), at(15 * .mm, 10 * .mm), net: 0),
			trace(at(5 * .mm, 10_500), at(15 * .mm, 10_500), net: 1),
		]

		let violations = design.check()
		XCTAssertEqual(violations.map(\.kind), [.clearance])
		XCTAssertEqual(violations[0].text, "GND 0.20 mm from VCC")
	}

	func testCopperExactlyTheClearanceApartIsCopperTheRuleAllows() {
		var design = design()
		design.board.traces = [
			trace(at(5 * .mm, 10 * .mm), at(15 * .mm, 10 * .mm), net: 0),
			trace(at(5 * .mm, 10_630), at(15 * .mm, 10_630), net: 1),
		]

		XCTAssertEqual(design.check(), [])
	}

	func testLooseningTheRuleSettlesWhatItHadComplainedOf() {
		var design = design()
		design.board.traces = [
			trace(at(5 * .mm, 10 * .mm), at(15 * .mm, 10 * .mm), net: 0),
			trace(at(5 * .mm, 10_500), at(15 * .mm, 10_500), net: 1),
		]
		XCTAssertEqual(design.check().count, 1)

		design.board.rules.clearance = 100
		XCTAssertEqual(design.check(), [])
	}

	func testTwoThroughPadsAreReportedOnceRatherThanOncePerLayerTheyReach() {
		var design = design(.analog)
		design.board.footprints = [
			part("J1", at: at(10 * .mm, 10 * .mm), net: 0),
			part("J2", at: at(10 * .mm, 11_700), net: 1),
		]

		let violations = design.check().filter { $0.kind == .clearance }
		XCTAssertEqual(violations.count, 1)
		XCTAssertEqual(violations[0].refs, [.footprint(0), .footprint(1)])
		XCTAssertEqual(violations[0].text, "GND 0.10 mm from VCC")
	}

	func testCopperPassingTooNearAHoleIsReported() {
		var design = design()
		design.board.holes = [Hole(at: at(10 * .mm, 10 * .mm), diameter: 3_200)]
		design.board.traces = [trace(at(5 * .mm, 12 * .mm), at(15 * .mm, 12 * .mm), net: 0)]

		let violations = design.check()
		XCTAssertEqual(violations.map(\.kind), [.hole])
		XCTAssertEqual(violations[0].text, "GND 0.25 mm from a hole")
	}

	func testCopperClearOfAHoleIsLeftAlone() {
		var design = design()
		design.board.holes = [Hole(at: at(10 * .mm, 10 * .mm), diameter: 3_200)]
		design.board.traces = [trace(at(5 * .mm, 12_200), at(15 * .mm, 12_200), net: 0)]

		XCTAssertEqual(design.check(), [])
	}

	func testCopperHangingOverTheCutEdgeIsReportedAsBeingOverIt() {
		var design = design()
		design.board.traces = [trace(at(100, 10 * .mm), at(5 * .mm, 10 * .mm), net: 0)]

		let violations = design.check()
		XCTAssertEqual(violations.map(\.kind), [.edge])
		XCTAssertEqual(violations[0].text, "GND over the edge")
	}

	func testCopperInsideTheBoardButTooNearTheEdgeIsReportedWithItsMargin() {
		var design = design()
		design.board.traces = [trace(at(300, 10 * .mm), at(5 * .mm, 10 * .mm), net: 0)]

		let violations = design.check()
		XCTAssertEqual(violations.map(\.kind), [.edge])
		XCTAssertEqual(violations[0].text, "GND 0.15 mm from the edge")
	}

	func testCopperRestingExactlyOnTheEdgeCountsAsOverIt() {
		var design = design()
		design.board.traces = [trace(at(150, 10 * .mm), at(5 * .mm, 10 * .mm), net: 0)]

		XCTAssertEqual(design.check().map(\.text), ["GND over the edge"])
	}

	func testCopperStandingClearOfTheEdgeIsLeftAlone() {
		var design = design()
		design.board.traces = [trace(at(600, 10 * .mm), at(5 * .mm, 10 * .mm), net: 0)]

		XCTAssertEqual(design.check(), [])
	}

	func testANetTheCopperDoesNotJoinIsReportedAsUnrouted() {
		var design = design()
		design.board.footprints = [
			part("J1", at: at(10 * .mm, 10 * .mm), net: 0),
			part("J2", at: at(30 * .mm, 10 * .mm), net: 0),
		]

		let violations = design.check()
		XCTAssertEqual(violations.map(\.kind), [.unrouted])
		XCTAssertEqual(violations[0].text, "GND not joined")
		XCTAssertEqual(violations[0].at, at(20 * .mm, 10 * .mm))
	}

	func testRoutingTheConnectionSettlesIt() {
		var design = design()
		design.board.footprints = [
			part("J1", at: at(10 * .mm, 10 * .mm), net: 0),
			part("J2", at: at(30 * .mm, 10 * .mm), net: 0),
		]
		design.board.traces = [trace(at(10 * .mm, 10 * .mm), at(30 * .mm, 10 * .mm), net: 0)]

		XCTAssertEqual(design.check(), [])
	}

	func testWhatIsUnroutedIsLeftOffTheCopperTheLayoutMarks() {
		var design = design()
		design.board.footprints = [
			part("J1", at: at(10 * .mm, 10 * .mm), net: 0),
			part("J2", at: at(30 * .mm, 10 * .mm), net: 0),
		]

		XCTAssertEqual(design.faults(), [])
		XCTAssertEqual(design.check().count, 1)
	}

	func testPadsJoinedOnlyToEachOtherStillMissTheSupplyPlaneTheyBelongTo() {
		var design = design(.digital)
		design.board.footprints = [
			part("C1", at: at(10 * .mm, 10 * .mm), net: 1, drill: 0),
			part("U1", at: at(30 * .mm, 10 * .mm), net: 1, drill: 0),
		]
		design.board.traces = [trace(at(10 * .mm, 10 * .mm), at(30 * .mm, 10 * .mm), net: 1)]

		let violations = design.check()
		XCTAssertEqual(violations.map(\.kind), [.unrouted])
		XCTAssertEqual(violations[0].text, "VCC not joined to its plane")
		XCTAssertEqual(violations[0].at, at(10 * .mm, 10 * .mm))
	}

	func testAViaDownToThePlaneSettlesTheSupply() {
		var design = design(.digital)
		design.board.footprints = [
			part("C1", at: at(10 * .mm, 10 * .mm), net: 1, drill: 0),
			part("U1", at: at(30 * .mm, 10 * .mm), net: 1, drill: 0),
		]
		design.board.traces = [trace(at(10 * .mm, 10 * .mm), at(30 * .mm, 10 * .mm), net: 1)]
		design.board.vias = [
			Via(at: at(30 * .mm, 10 * .mm), net: 1),
		]

		XCTAssertEqual(design.check(), [])
	}

	func testANetWithNoPlaneOfItsOwnIsAskedOnlyToReachItsOwnPads() {
		var design = design(.digital)
		design.board.footprints = [
			part("C1", at: at(10 * .mm, 10 * .mm), net: 2, drill: 0),
			part("U1", at: at(30 * .mm, 10 * .mm), net: 2, drill: 0),
		]
		design.board.traces = [trace(at(10 * .mm, 10 * .mm), at(30 * .mm, 10 * .mm), net: 2)]

		XCTAssertEqual(design.check(), [])
	}

	func testTheWorstIsListedFirstAndTheOrderIsTheSameEveryTime() {
		var design = design()
		design.board.footprints = [
			part("J1", at: at(30 * .mm, 30 * .mm), net: 2),
			part("J2", at: at(40 * .mm, 30 * .mm), net: 2),
		]
		design.board.traces = [
			trace(at(5 * .mm, 10 * .mm), at(15 * .mm, 10 * .mm), net: 0),
			trace(at(10 * .mm, 5 * .mm), at(10 * .mm, 15 * .mm), net: 1),
			trace(at(20 * .mm, 20 * .mm), at(30 * .mm, 20 * .mm), net: 0),
			trace(at(20 * .mm, 20_500), at(30 * .mm, 20_500), net: 1),
			trace(at(300, 35 * .mm), at(5 * .mm, 35 * .mm), net: 0),
		]

		XCTAssertEqual(design.check().map(\.kind), [.short, .clearance, .edge, .unrouted])
		XCTAssertEqual(design.check(), design.check())
	}
}
