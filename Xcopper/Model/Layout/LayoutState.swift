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
		case .trace: "W"
		case .via: "V"
		case .hole: "H"
		case .footprint: "F"
		}
	}
}

extension Nm {

	static var placementGrids: [Nm] {
		[.mm(1.27), .mm(2.54), .mm(12.7)]
	}

	static var routingGrids: [Nm] {
		[.mm(0.127), .mm(0.254), .mm(0.635)]
	}

	static var widths: [Nm] {
		[.mm(0.4), .mm(1.2)]
	}

	static var clearances: [Nm] {
		[.mm(0.3), .mm(0.6)]
	}

	static var sheetSnapGrids: [Nm] {
		[.mil(50), .mil(100)]
	}

	static var displayGrids: [Nm] {
		[.mil(100), .inches(1)]
	}

	var label: String {
		let mm = mm
		return mm < 0.1
			? String(format: "%.3f", mm)
			: String(format: "%.3g", mm)
	}
}

struct LayoutState: Equatable, SelectionState {
	var tool: Tool = .select {
		didSet {
			guard tool != oldValue else { return }
			cancelSessions()
		}
	}
	var layer: Int = 0
	var net: Net.ID?
	var placementGrid: Nm = .placementGrids.first!
	var routingGrid: Nm = .routingGrids.last!
	var grid: Nm = .displayGrids.first!
	var traceWidth: Nm = .widths.first!
	var spec: Footprint.Spec = .default
	var selection: Set<Ref> = []
	var traceSession: TraceSession?
	var selectSession: SelectSession<Ref>?
	var moveSession: MoveSession?
	var viewport: Viewport = .init()
}

extension LayoutState {

	private var usesPlacementGrid: Bool {
		switch tool {
		case .footprint, .hole: true
		case .trace, .via: false
		case .select: selection.usesPlacementGrid
		}
	}

	var activeGrid: Nm {
		get { usesPlacementGrid ? placementGrid : routingGrid }
		set {
			if usesPlacementGrid { placementGrid = newValue }
			else { routingGrid = newValue }
		}
	}

	var activeGridOptions: [Nm] { usesPlacementGrid ? Nm.placementGrids : Nm.routingGrids }
	var selectionGrid: Nm { selection.usesPlacementGrid ? placementGrid : routingGrid }

	mutating func cancelSessions() {
		traceSession = nil
		selectSession = nil
		moveSession = nil
	}

	mutating func prevLayer(_ stack: Stack) {
		step(stack, by: -1)
	}

	mutating func nextLayer(_ stack: Stack) {
		step(stack, by: 1)
	}

	mutating func clampLayer(_ stack: Stack) {
		layer = stack.isSignal(layer) ? layer : stack.bottom
	}

	private mutating func step(_ stack: Stack, by offset: Int) {
		let signals = stack.signals
		let index = signals.firstIndex(of: layer) ?? 0
		layer = signals[(index + offset + signals.count) % signals.count]
	}
}

private extension Set where Element == Ref {

	var usesPlacementGrid: Bool {
		isEmpty || contains { ref in
			switch ref {
			case .footprint, .hole, .module, .pad: true
			case .trace, .via: false
			}
		}
	}
}

extension LayoutState {

	mutating func beginTrace(at point: Point) {
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

	mutating func updateTrace(to point: Point) {
		guard var session = traceSession else { return }
		session.end = point
		if case let .gesture(committable) = session.phase {
			session.phase = .gesture(committable: committable || session.didDraw)
		}
		traceSession = session
	}

	mutating func hoverTrace(to point: Point) {
		guard traceSession?.phase == .pending else { return }
		updateTrace(to: point)
	}

	mutating func endTrace() -> Trace? {
		guard let session = traceSession, case let .gesture(committable) = session.phase else {
			return nil
		}
		guard committable, session.didDraw else {
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
