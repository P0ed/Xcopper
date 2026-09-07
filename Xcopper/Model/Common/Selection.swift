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
	var start: Point
	var end: Point
	var mode: SelectionMode
	var initial: Set<R>

	var didDrag: Bool { start != end }
	var rect: Rect { Rect(from: start, to: end) }
}

struct MoveSession: Equatable {
	var start: Point
	var end: Point

	var delta: Point { end - start }
	var didMove: Bool { start != end }
}

protocol SelectionState {
	associatedtype SelectionRef: Hashable
	var selection: Set<SelectionRef> { get set }
	var selectSession: SelectSession<SelectionRef>? { get set }
	var moveSession: MoveSession? { get set }
	mutating func cancelSessions()
}

extension SelectionState {

	mutating func resetTransientInteractions() {
		selection = []
		cancelSessions()
	}

	mutating func beginSelect(at point: Point, mode: SelectionMode) {
		guard selectSession == nil else { return }
		selectSession = SelectSession(start: point, end: point, mode: mode, initial: selection)
	}

	mutating func updateSelect(to point: Point) {
		selectSession?.end = point
	}

	mutating func endSelect(at point: Point) -> SelectSession<SelectionRef>? {
		defer { selectSession = nil }
		updateSelect(to: point)
		return selectSession
	}

	mutating func beginMove(at point: Point) {
		guard moveSession == nil else { return }
		moveSession = MoveSession(start: point, end: point)
	}

	mutating func updateMove(to point: Point) {
		moveSession?.end = point
	}

	mutating func endMove(at point: Point) -> MoveSession? {
		defer { moveSession = nil }
		updateMove(to: point)
		return moveSession
	}
}

enum RoutePhase: Equatable {
	case pending
	case gesture(committable: Bool)
}

struct TraceSession: Equatable {
	var start: Point
	var end: Point
	var layer: Int
	var net: Net.ID?
	var phase: RoutePhase

	var didDraw: Bool { start != end }
}

struct WireSession: Equatable {
	var start: Point
	var end: Point
	var phase: RoutePhase
	var heading: Point = .zero

	var points: [Point] { RoutingAngles.orthogonal.path(from: start, to: end, heading: heading) }
	var wires: [Wire] { zip(points, points.dropFirst()).map { Wire(start: $0.0, end: $0.1) } }

	var didDraw: Bool { start != end }
}

extension Set where Element == Ref {
	var containsPads: Bool { contains { $0.kind == .pad } }
	var group: (kind: Ref.Kind, indices: [Int])? {
		guard let kind = first?.kind, kind != .module, kind != .pad, allSatisfy({ $0.kind == kind }) else { return nil }
		return (kind, map(\.index).sorted())
	}
}

extension Set where Element == Schematic.Ref {
	var group: (kind: Schematic.Ref.Kind, indices: [Int])? {
		guard let kind = first?.kind, kind != .module, allSatisfy({ $0.kind == kind }) else { return nil }
		return (kind, map(\.index).sorted())
	}
}
