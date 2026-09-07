enum SchematicTool: Hashable, CaseIterable, ToolKind {
	case select, wire, label, symbol
}

extension SchematicTool {

	var actionName: String {
		switch self {
		case .select: "Select"
		case .wire: "Wire"
		case .label: "Label"
		case .symbol: "Place"
		}
	}

	var systemImage: String {
		switch self {
		case .select: "rectangle.dashed"
		case .wire: "line.diagonal"
		case .label: "tag"
		case .symbol: "square.on.circle"
		}
	}

	var shortcutCharacter: Character {
		switch self {
		case .select: "S"
		case .wire: "W"
		case .label: "L"
		case .symbol: "F"
		}
	}
}

struct SchematicState: Equatable, SelectionState {
	var tool: SchematicTool = .select {
		didSet {
			guard tool != oldValue else { return }
			cancelSessions()
		}
	}
	var snap: Nm = .sheetSnapGrids.last!
	var grid: Nm = .displayGrids.first!
	var spec: Symbol.Spec = .default
	var label: String = "NET"
	var selection: Set<Schematic.Ref> = []
	var wireSession: WireSession?
	var selectSession: SelectSession<Schematic.Ref>?
	var moveSession: MoveSession?
	var viewport: Viewport = .init()
}

extension SchematicState {

	mutating func cancelSessions() {
		wireSession = nil
		selectSession = nil
		moveSession = nil
	}

	mutating func beginWire(at point: Point) {
		if let session = wireSession, session.phase == .pending {
			wireSession = WireSession(
				start: session.start,
				end: point,
				phase: .gesture(committable: true),
				heading: session.heading
			)
		} else if wireSession == nil {
			wireSession = WireSession(start: point, end: point, phase: .gesture(committable: false))
		}
	}

	mutating func updateWire(to point: Point) {
		guard var session = wireSession else { return }
		session.end = point
		if session.heading == .zero, session.didDraw {
			session.heading = (snapped90(from: session.start, to: point) - session.start).heading
		}
		if case let .gesture(committable) = session.phase {
			session.phase = .gesture(committable: committable || point != session.start)
		}
		wireSession = session
	}

	mutating func hoverWire(to point: Point) {
		guard wireSession?.phase == .pending else { return }
		updateWire(to: point)
	}

	mutating func endWire() -> [Wire]? {
		guard let session = wireSession, case let .gesture(committable) = session.phase else {
			return nil
		}
		guard committable, session.didDraw else {
			wireSession = modifying(session) { session in session.phase = .pending }
			return nil
		}
		let wires = session.wires
		wireSession = WireSession(start: session.end, end: session.end, phase: .pending)
		return wires
	}
}
