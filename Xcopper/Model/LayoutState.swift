import SwiftUI

enum Tool: Hashable, CaseIterable, ToolKind {
	case select, trace, via, hole, footprint
}

extension Tool {

	var actionName: String {
		switch self {
		case .select: "Select"
		case .trace: "Route"
		case .via: "Via"
		case .hole: "Hole"
		case .footprint: "Place"
		}
	}

	var systemImage: String {
		switch self {
		case .select: "rectangle.dashed"
		case .trace: "line.diagonal"
		case .via: "circle.circle"
		case .hole: "circle.dashed"
		case .footprint: "square.grid.3x3.square"
		}
	}

	var shortcutCharacter: Character {
		switch self {
		case .select: "S"
		case .trace: "T"
		case .via: "V"
		case .hole: "H"
		case .footprint: "F"
		}
	}
}

extension Nm {

	static var snapGrids: [Nm] {
		[.mil(5), .mil(10), .mil(25), .mil(50), .mil(100)]
	}

	static var widths: [Nm] {
		[.mm(0.33), .mm(0.47), .mm(0.68), .mm(1.0), .mm(1.5), .mm(2.2)]
	}

	static var sheetSnapGrids: [Nm] {
		[.mil(50), .mil(100)]
	}

	static var displayGrids: [Nm] {
		[.mm(1.27), .mm(2.54)]
	}

	var coordinate: String { String(format: "%.2f", mm) }

	var label: String {
		let mm = mm
		return mm < 0.1
			? String(format: "%.3f", mm)
			: String(format: "%.3g", mm)
	}
}

struct LayoutState: Equatable {
	var tool: Tool = .select {
		didSet {
			guard tool != oldValue else { return }
			cancelSessions()
		}
	}
	var layer: Int = 0
	var net: Net.ID?
	var snap: Nm = .mil(10)
	var grid: Nm = .mm(1.27)
	var traceWidth: Nm = .mm(0.25)
	var spec: Footprint.Spec = .default
	var selection: Set<Ref> = []
	var traceSession: TraceSession?
	var selectSession: SelectSession<Ref>?
	var moveSession: MoveSession?
	var viewport: Viewport = .init()
}

extension LayoutState {

	mutating func cancelSessions() {
		traceSession = nil
		selectSession = nil
		moveSession = nil
	}

	mutating func resetTransientInteractions() {
		selection = []
		cancelSessions()
	}

	mutating func prevLayer(_ stack: Stack) {
		layer = (layer + stack.count - 1) % stack.count
	}

	mutating func nextLayer(_ stack: Stack) {
		layer = (layer + 1) % stack.count
	}

	mutating func clampLayer(_ stack: Stack) {
		layer = min(layer, stack.bottom)
	}
}

extension LayoutState {

	mutating func beginSelect(at point: Pt, mode: SelectionMode) {
		guard selectSession == nil else { return }
		selectSession = SelectSession(start: point, end: point, mode: mode, initial: selection)
	}

	mutating func updateSelect(to point: Pt) {
		guard var session = selectSession, session.end != point else { return }
		session.end = point
		selectSession = session
	}

	mutating func beginMove(at point: Pt) {
		guard moveSession == nil else { return }
		moveSession = MoveSession(start: point, end: point)
	}

	mutating func updateMove(to point: Pt) {
		guard var session = moveSession, session.end != point else { return }
		session.end = point
		moveSession = session
	}

	mutating func beginTrace(at point: Pt) {
		if let session = traceSession, session.phase == .pending {
			traceSession = TraceSession(
				start: session.start,
				end: point,
				layer: session.layer,
				net: session.net,
				phase: .gesture(committable: true)
			)
		} else if traceSession == nil {
			traceSession = TraceSession(
				start: point,
				end: point,
				layer: layer,
				net: net,
				phase: .gesture(committable: false)
			)
		}
	}

	mutating func updateTrace(to point: Pt) {
		guard var session = traceSession else { return }
		session.end = point
		if case let .gesture(committable) = session.phase {
			session.phase = .gesture(committable: committable || point != session.start)
		}
		traceSession = session
	}

	mutating func hoverTrace(to point: Pt) {
		guard traceSession?.phase == .pending else { return }
		updateTrace(to: point)
	}

	/// Commits the current segment and keeps routing from its end
	mutating func endTrace() -> Trace? {
		guard let session = traceSession, case let .gesture(committable) = session.phase else {
			return nil
		}
		guard committable else {
			traceSession = modifying(session) { session in session.phase = .pending }
			return nil
		}
		traceSession = TraceSession(
			start: session.end,
			end: session.end,
			layer: session.layer,
			net: session.net,
			phase: .pending
		)
		return Trace(
			start: session.start,
			end: session.end,
			width: traceWidth,
			layer: session.layer,
			net: session.net
		)
	}
}
