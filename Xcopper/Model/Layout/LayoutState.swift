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
		[127, 254, 635]
	}

	static var traceWidths: [µm] {
		[400, 500, 1_200, 2_000]
	}

	static var clearances: [µm] {
		[300, 400, 500]
	}

	static var sheetSnapGrids: [µm] {
		[1_270, 2_540]
	}

	static var displayGrids: [µm] {
		[2_540, 1 * .inch]
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
			guard tool != oldValue else { return }
			cancelSessions()
		}
	}
	var layer: Int = 0
	var net: Net.ID?
	var placementGrid: µm = .placementGrids.first!
	var routingGrid: µm = .routingGrids.last!
	var grid: µm = .displayGrids.first!
	var hiddenLayers: Int = 0
	var silkscreen = true
	var traceWidth: µm?
	var spec: Footprint.Spec = .default
	var selection: Set<Ref> = []
	var traceSession: TraceSession?
	var selectSession: SelectSession<Ref>?
	var moveSession: MoveSession?
	var viewport: Viewport = .init()
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
		switch tool {
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
