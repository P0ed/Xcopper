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

extension µm {

	static var placementGrids: [µm] {
		[1_270, 2_540, 12_700]
	}

	static var routingGrids: [µm] {
		[100, 127, 254, 635]
	}

	static var traceWidths: [µm] {
		[400, 500, 600, 800, 1_000, 1_200, 2_000]
	}

	static var clearances: [µm] {
		[300, 400, 500]
	}

	static var sheetSnapGrids: [µm] {
		[1_270, 2_540]
	}

	static var displayGrids: [µm] {
		[10_000, 12_700, 25_400]
	}

	var label: String {
		let mm: Double = .mm(self)
		return mm < 0.1
			? String(format: "%.3f", mm)
			: String(format: "%.3g", mm)
	}
}

struct LayoutState: Equatable, SelectionState {
	var tool: Tool = .select {
		didSet {
			guard tool != oldValue || modulePlacement != nil else { return }
			cancelSessions()
		}
	}
	var stack: Stack
	var layer: Int = 0
	var net: Net.ID?
	var placementGrid: µm = .placementGrids.first!
	var routingGrid: µm = .routingGrids.last!
	var grid: µm = .displayGrids.last!
	var hiddenLayers: Int
	var silkscreen = false
	var ratsnest = true
	var traceWidth: µm?
	var spec: Footprint.Spec = .default
	var selection: Set<Ref> = []
	var traceSession: TraceSession?
	var selectSession: SelectSession<Ref>?
	var moveSession: MoveSession?
	var modulePlacement: ModulePlacement?
	var viewport: LayoutViewport = .init()

	init(stack: Stack = .analog) {
		self.stack = stack
		hiddenLayers = stack.internals.reduce(0) { $0 | 1 << $1 }
	}
}

extension LayoutState {

	subscript(visible layer: Int) -> Bool {
		get { hiddenLayers & 1 << layer == 0 }
		set {
			if newValue { hiddenLayers &= ~(1 << layer) }
			else { hiddenLayers |= 1 << layer }
		}
	}

	private var usesPlacementGrid: Bool {
		if modulePlacement != nil { return true }
		return switch tool {
		case .footprint, .hole: true
		case .trace, .via: false
		case .select: selection.usesPlacementGrid
		}
	}

	var activeGrid: µm {
		get { usesPlacementGrid ? placementGrid : routingGrid }
		set {
			if usesPlacementGrid { placementGrid = newValue }
			else { routingGrid = newValue }
		}
	}

	var activeGridOptions: [µm] { usesPlacementGrid ? µm.placementGrids : µm.routingGrids }
	var selectionGrid: µm { selection.usesPlacementGrid ? placementGrid : routingGrid }

	mutating func cancelSessions() {
		traceSession = nil
		selectSession = nil
		moveSession = nil
		modulePlacement = nil
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
		if var session = traceSession, session.phase == .pending {
			session.end = point
			session.phase = .gesture(committable: true)
			traceSession = session
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
		guard var session = traceSession, case let .gesture(committable) = session.phase else {
			return nil
		}
		guard committable, session.didDraw else {
			traceSession = modifying(session) { session in session.phase = .pending }
			return nil
		}
		let trace = Trace(
			start: session.start,
			end: session.end,
			width: traceWidth,
			layer: session.layer,
			net: session.net
		)
		session.anchors.append(session.start)
		session.start = session.end
		session.phase = .pending
		traceSession = session
		return trace
	}

	mutating func backtrackTrace(in board: inout Board) {
		guard var session = traceSession, let start = session.anchors.last,
			let trace = board.traces.last,
			trace.start == start, trace.end == session.start, trace.layer == session.layer
		else { return }

		board.traces.removeLast()
		session.anchors.removeLast()
		session.start = trace.start
		session.end = trace.end
		session.net = trace.net
		session.phase = .pending
		traceSession = session
		traceWidth = trace.width
		layer = trace.layer
		net = trace.net
		viewport.cursor = trace.end
	}
}
