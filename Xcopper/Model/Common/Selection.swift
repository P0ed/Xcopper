enum SelectionMode: Equatable {
	case replace, union, subtract

	init(shift: Bool, option: Bool) {
		self = option ? .subtract : shift ? .union : .replace
	}

	func apply<R: Hashable>(_ current: Set<R>, _ hit: Set<R>) -> Set<R> {
		switch self {
		case .replace: hit
		case .union: current.union(hit)
		case .subtract: current.subtracting(hit)
		}
	}
}

struct SelectSession<R: Hashable>: Equatable {
	var start: Pt
	var end: Pt
	var mode: SelectionMode
	var initial: Set<R>

	var didDrag: Bool { start != end }
	var rect: Rect { Rect(from: start, to: end) }
}

struct MoveSession: Equatable {
	var start: Pt
	var end: Pt

	var delta: Pt { end - start }
	var didMove: Bool { start != end }
}

enum RoutePhase: Equatable {
	case pending
	case gesture(committable: Bool)
}

struct TraceSession: Equatable {
	var start: Pt
	var end: Pt
	var layer: Int
	var net: Net.ID?
	var phase: RoutePhase

	var didDraw: Bool { start != end }
}

struct WireSession: Equatable {
	var start: Pt
	var end: Pt
	var phase: RoutePhase

	var didDraw: Bool { start != end }
}
