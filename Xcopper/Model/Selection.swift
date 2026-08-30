enum SelectionMode: Equatable {
	case replace, union, subtract

	init(shift: Bool, option: Bool) {
		self = option ? .subtract : shift ? .union : .replace
	}

	func apply(_ current: Set<Ref>, _ hit: Set<Ref>) -> Set<Ref> {
		switch self {
		case .replace: hit
		case .union: current.union(hit)
		case .subtract: current.subtracting(hit)
		}
	}
}

struct SelectSession: Equatable {
	var start: Pt
	var end: Pt
	var mode: SelectionMode
	var initial: Set<Ref>

	var didDrag: Bool { start != end }
	var rect: Rect { Rect(from: start, to: end) }
}

struct MoveSession: Equatable {
	var start: Pt
	var end: Pt

	var delta: Pt { end - start }
	var didMove: Bool { start != end }
}

struct TraceSession: Equatable {
	enum Phase: Equatable {
		case pending
		case gesture(committable: Bool)
	}

	var start: Pt
	var end: Pt
	var layer: Int
	var net: Net.ID?
	var phase: Phase
}
