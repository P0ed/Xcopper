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

struct SchematicState: Equatable {
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

	mutating func resetTransientInteractions() {
		selection = []
		cancelSessions()
	}

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

	mutating func beginWire(at point: Pt) {
		if let session = wireSession, session.phase == .pending {
			wireSession = WireSession(
				start: session.start,
				end: point,
				phase: .gesture(committable: true)
			)
		} else if wireSession == nil {
			wireSession = WireSession(start: point, end: point, phase: .gesture(committable: false))
		}
	}

	mutating func updateWire(to point: Pt) {
		guard var session = wireSession else { return }
		session.end = point
		if case let .gesture(committable) = session.phase {
			session.phase = .gesture(committable: committable || point != session.start)
		}
		wireSession = session
	}

	mutating func hoverWire(to point: Pt) {
		guard wireSession?.phase == .pending else { return }
		updateWire(to: point)
	}

	mutating func endWire() -> Wire? {
		guard let session = wireSession, case let .gesture(committable) = session.phase else {
			return nil
		}
		guard committable else {
			wireSession = modifying(session) { session in session.phase = .pending }
			return nil
		}
		wireSession = WireSession(start: session.end, end: session.end, phase: .pending)
		return Wire(start: session.start, end: session.end)
	}
}
