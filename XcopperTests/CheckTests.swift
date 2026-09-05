import XCTest
@testable import Xcopper

final class CheckTests: XCTestCase {

	private func design(_ stack: Stack = .classic) -> Design {
		Design(board: Board(size: Size(width: .mm(50), height: .mm(40)), stack: stack))
	}

	private func at(_ x: Double, _ y: Double) -> Pt { Pt(x: .mm(x), y: .mm(y)) }

	private func trace(
		_ from: Pt,
		_ to: Pt,
		net: Net.ID?,
		layer: Int = 0,
		width: Nm = .mm(0.3)
	) -> Trace {
		Trace(start: from, end: to, width: width, layer: layer, net: net)
	}

	private func part(_ reference: String, at: Pt, net: Net.ID?, pad: Nm = .mm(1.6)) -> Footprint {
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
					drill: .mm(0.8),
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
			gap(.round(at(10.0, 10.0), .mm(2.0)), .round(at(20.0, 10.0), .mm(4.0))),
			Double(Int.mm(7.0)),
			accuracy: 1.0
		)
	}

	func testCopperThatOverlapsLeavesNoGapAtAll() {
		XCTAssertEqual(gap(.round(at(10.0, 10.0), .mm(2.0)), .round(at(10.5, 10.0), .mm(2.0))), 0.0)
	}

	func testTwoTracksCrossingLeaveNoGapEvenWhereNeitherEndIsNearTheOther() {
		XCTAssertEqual(
			gap(
				.segment(at(5.0, 10.0), at(15.0, 10.0), .mm(0.3)),
				.segment(at(10.0, 5.0), at(10.0, 15.0), .mm(0.3))
			),
			0.0
		)
	}

	func testASquarePadIsMeasuredFromItsEdgeAndNotItsCorner() {
		XCTAssertEqual(
			gap(
				.rect(Rect(center: at(10.0, 10.0), size: Size(width: .mm(2.0), height: .mm(2.0)))),
				.round(at(13.0, 10.0), .mm(1.0))
			),
			Double(Int.mm(1.5)),
			accuracy: 1.0
		)
	}

	func testAPadDrawnWithNoSizeAtAllHoldsNothingAndShortsNothing() {
		XCTAssertEqual(
			gap(.rect(Rect(center: at(10.0, 10.0), size: .zero)), .round(at(20.0, 10.0), .mm(2.0))),
			Double(Int.mm(9.0)),
			accuracy: 1.0
		)
	}

	func testCopperOfTwoNetsCrossingIsReportedAsAShortWhereItCrosses() {
		var design = design()
		design.board.traces = [
			trace(at(5.0, 10.0), at(15.0, 10.0), net: 0),
			trace(at(10.0, 5.0), at(10.0, 15.0), net: 1),
		]

		let violations = design.check()
		XCTAssertEqual(violations.map(\.kind), [.short])
		XCTAssertEqual(violations[0].text, "GND meets VCC")
		XCTAssertEqual(violations[0].at, at(10.0, 10.0))
		XCTAssertEqual(violations[0].layer, 0)
	}

	func testAShortNamesBothPiecesOfCopperSoAClickPicksThemUp() {
		var design = design()
		design.board.traces = [
			trace(at(5.0, 10.0), at(15.0, 10.0), net: 0),
			trace(at(10.0, 5.0), at(10.0, 15.0), net: 1),
		]

		XCTAssertEqual(design.check().first?.refs, [.trace(0), .trace(1)])
	}

	func testCopperOfOneNetMayTouchItself() {
		var design = design()
		design.board.traces = [
			trace(at(5.0, 10.0), at(15.0, 10.0), net: 0),
			trace(at(10.0, 5.0), at(10.0, 15.0), net: 0),
		]

		XCTAssertEqual(design.check(), [])
	}

	func testCopperTheDesignHasNotNamedIsNotJudgedAgainstAnything() {
		var design = design()
		design.board.traces = [
			trace(at(5.0, 10.0), at(15.0, 10.0), net: nil),
			trace(at(10.0, 5.0), at(10.0, 15.0), net: 1),
		]

		XCTAssertEqual(design.check(), [])
	}

	func testCopperOnTwoLayersMayCrossFreely() {
		var design = design()
		design.board.traces = [
			trace(at(5.0, 10.0), at(15.0, 10.0), net: 0, layer: 0),
			trace(at(10.0, 5.0), at(10.0, 15.0), net: 1, layer: 1),
		]

		XCTAssertEqual(design.check(), [])
	}

	func testCopperRunningTooCloseToAnotherNetIsReportedWithTheGapItLeaves() {
		var design = design()
		design.board.traces = [
			trace(at(5.0, 10.0), at(15.0, 10.0), net: 0),
			trace(at(5.0, 10.5), at(15.0, 10.5), net: 1),
		]

		let violations = design.check()
		XCTAssertEqual(violations.map(\.kind), [.clearance])
		XCTAssertEqual(violations[0].text, "GND 0.20 mm from VCC")
	}

	func testCopperExactlyTheClearanceApartIsCopperTheRuleAllows() {
		var design = design()
		design.board.traces = [
			trace(at(5.0, 10.0), at(15.0, 10.0), net: 0),
			trace(at(5.0, 10.63), at(15.0, 10.63), net: 1),
		]

		XCTAssertEqual(design.check(), [])
	}

	func testLooseningTheRuleSettlesWhatItHadComplainedOf() {
		var design = design()
		design.board.traces = [
			trace(at(5.0, 10.0), at(15.0, 10.0), net: 0),
			trace(at(5.0, 10.5), at(15.0, 10.5), net: 1),
		]
		XCTAssertEqual(design.check().count, 1)

		design.board.rules.clearance = .mm(0.1)
		XCTAssertEqual(design.check(), [])
	}

	func testTwoThroughPadsAreReportedOnceRatherThanOncePerLayerTheyReach() {
		var design = design(.analog)
		design.board.footprints = [
			part("J1", at: at(10.0, 10.0), net: 0),
			part("J2", at: at(10.0, 11.7), net: 1),
		]

		let violations = design.check().filter { $0.kind == .clearance }
		XCTAssertEqual(violations.count, 1)
		XCTAssertEqual(violations[0].refs, [.footprint(0), .footprint(1)])
		XCTAssertEqual(violations[0].text, "GND 0.10 mm from VCC")
	}

	func testCopperPassingTooNearAHoleIsReported() {
		var design = design()
		design.board.holes = [Hole(at: at(10.0, 10.0), diameter: .mm(3.2))]
		design.board.traces = [trace(at(5.0, 12.0), at(15.0, 12.0), net: 0)]

		let violations = design.check()
		XCTAssertEqual(violations.map(\.kind), [.hole])
		XCTAssertEqual(violations[0].text, "GND 0.25 mm from a hole")
	}

	func testCopperClearOfAHoleIsLeftAlone() {
		var design = design()
		design.board.holes = [Hole(at: at(10.0, 10.0), diameter: .mm(3.2))]
		design.board.traces = [trace(at(5.0, 12.2), at(15.0, 12.2), net: 0)]

		XCTAssertEqual(design.check(), [])
	}

	func testCopperHangingOverTheCutEdgeIsReportedAsBeingOverIt() {
		var design = design()
		design.board.traces = [trace(at(0.1, 10.0), at(5.0, 10.0), net: 0)]

		let violations = design.check()
		XCTAssertEqual(violations.map(\.kind), [.edge])
		XCTAssertEqual(violations[0].text, "GND over the edge")
	}

	func testCopperInsideTheBoardButTooNearTheEdgeIsReportedWithItsMargin() {
		var design = design()
		design.board.traces = [trace(at(0.3, 10.0), at(5.0, 10.0), net: 0)]

		let violations = design.check()
		XCTAssertEqual(violations.map(\.kind), [.edge])
		XCTAssertEqual(violations[0].text, "GND 0.15 mm from the edge")
	}

	func testCopperRestingExactlyOnTheEdgeCountsAsOverIt() {
		var design = design()
		design.board.traces = [trace(at(0.15, 10.0), at(5.0, 10.0), net: 0)]

		XCTAssertEqual(design.check().map(\.text), ["GND over the edge"])
	}

	func testCopperStandingClearOfTheEdgeIsLeftAlone() {
		var design = design()
		design.board.traces = [trace(at(0.6, 10.0), at(5.0, 10.0), net: 0)]

		XCTAssertEqual(design.check(), [])
	}

	func testANetTheCopperDoesNotJoinIsReportedAsUnrouted() {
		var design = design()
		design.board.footprints = [
			part("J1", at: at(10.0, 10.0), net: 0),
			part("J2", at: at(30.0, 10.0), net: 0),
		]

		let violations = design.check()
		XCTAssertEqual(violations.map(\.kind), [.unrouted])
		XCTAssertEqual(violations[0].text, "GND not joined")
		XCTAssertEqual(violations[0].at, at(20.0, 10.0))
	}

	func testRoutingTheConnectionSettlesIt() {
		var design = design()
		design.board.footprints = [
			part("J1", at: at(10.0, 10.0), net: 0),
			part("J2", at: at(30.0, 10.0), net: 0),
		]
		design.board.traces = [trace(at(10.0, 10.0), at(30.0, 10.0), net: 0)]

		XCTAssertEqual(design.check(), [])
	}

	func testWhatIsUnroutedIsLeftOffTheCopperTheLayoutMarks() {
		var design = design()
		design.board.footprints = [
			part("J1", at: at(10.0, 10.0), net: 0),
			part("J2", at: at(30.0, 10.0), net: 0),
		]

		XCTAssertEqual(design.faults(), [])
		XCTAssertEqual(design.check().count, 1)
	}

	func testTheWorstIsListedFirstAndTheOrderIsTheSameEveryTime() {
		var design = design()
		design.board.footprints = [
			part("J1", at: at(30.0, 30.0), net: 2),
			part("J2", at: at(40.0, 30.0), net: 2),
		]
		design.board.traces = [
			trace(at(5.0, 10.0), at(15.0, 10.0), net: 0),
			trace(at(10.0, 5.0), at(10.0, 15.0), net: 1),
			trace(at(20.0, 20.0), at(30.0, 20.0), net: 0),
			trace(at(20.0, 20.5), at(30.0, 20.5), net: 1),
			trace(at(0.3, 35.0), at(5.0, 35.0), net: 0),
		]

		XCTAssertEqual(design.check().map(\.kind), [.short, .clearance, .edge, .unrouted])
		XCTAssertEqual(design.check(), design.check())
	}
}
