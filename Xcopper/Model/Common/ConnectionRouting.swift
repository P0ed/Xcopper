import Foundation

struct ConnectionRoutingRequest: Sendable {
	var board: Board
	var from: CopperIsland
	var to: CopperIsland?
	var layers: [Int]
	var width: µm
	var clearance: µm
	var viaLimit: Int = 4
	var grid: µm = 100
	var maxNodes: Int = 200_000
}

struct PlannedConnection: Sendable {
	var traces: [Trace] = []
	var vias: [Via] = []
	var visited = 0
	var length: Double { traces.reduce(0) { $0 + Double($1.start.distanceSquared(to: $1.end)).squareRoot() } }
}

struct ConnectionRoutingFailure: Error {
	var code: String
	var visited: Int
}

private struct RoutingNode: Hashable {
	var point: Point
	var layer: Int
	var heading: Int
	var vias: Int
}

private struct RoutingQueue {
	struct Item {
		var node: RoutingNode
		var cost: Double
		var score: Double
		var order: Int
	}
	var items: [Item] = []
	var sequence = 0
	func less(_ a: Item, _ b: Item) -> Bool { a.score != b.score ? a.score < b.score : a.order < b.order }
	mutating func push(_ node: RoutingNode, cost: Double, score: Double) {
		sequence += 1
		items.append(Item(node: node, cost: cost, score: score, order: sequence))
		var index = items.count - 1
		while index > 0 {
			let parent = (index - 1) / 2
			guard less(items[index], items[parent]) else { break }
			items.swapAt(index, parent)
			index = parent
		}
	}
	mutating func pop() -> Item? {
		guard !items.isEmpty else { return nil }
		if items.count == 1 { return items.removeLast() }
		let result = items[0]
		items[0] = items.removeLast()
		var index = 0
		while index * 2 + 1 < items.count {
			let left = index * 2 + 1, right = left + 1
			let child = right < items.count && less(items[right], items[left]) ? right : left
			guard less(items[child], items[index]) else { break }
			items.swapAt(index, child)
			index = child
		}
		return result
	}
}

private struct RoutingCell: Hashable {
	var x: Int
	var y: Int
}

private struct RoutingObstacles {
	var objects: [BoardObject]
	var buckets: [RoutingCell: [Int]] = [:]
	var global: [Int] = []
	let pitch = 2_000
	var clearance: µm
	var bounds: Rect

	init(_ request: ConnectionRoutingRequest) {
		objects = request.board.objects.filter { $0.drilled || $0.net != request.from.net }
		clearance = request.clearance
		bounds = request.board.bounds
		for (index, object) in objects.enumerated() {
			if cellCount(object.bounds) > 4096 { global.append(index) }
			else { for cell in cells(object.bounds) { buckets[cell, default: []].append(index) } }
		}
	}

	func cellCount(_ rect: Rect) -> Int {
		let columns = Int(floor(Double(rect.maxX) / Double(pitch)) - floor(Double(rect.minX) / Double(pitch))) + 1
		let rows = Int(floor(Double(rect.maxY) / Double(pitch)) - floor(Double(rect.minY) / Double(pitch))) + 1
		return columns * rows
	}

	func cells(_ rect: Rect) -> [RoutingCell] {
		let minX = Int(floor(Double(rect.minX) / Double(pitch))), maxX = Int(floor(Double(rect.maxX) / Double(pitch)))
		let minY = Int(floor(Double(rect.minY) / Double(pitch))), maxY = Int(floor(Double(rect.maxY) / Double(pitch)))
		return (minX ... maxX).flatMap { x in (minY ... maxY).map { RoutingCell(x: x, y: $0) } }
	}

	func allows(_ figure: Figure, layers: ClosedRange<Int>) -> Bool {
		let extent = figure.bounds
		guard extent.minX >= bounds.minX + clearance, extent.maxX <= bounds.maxX - clearance,
			extent.minY >= bounds.minY + clearance, extent.maxY <= bounds.maxY - clearance else { return false }
		let searchBounds = extent.outset(clearance)
		var candidates = global
		if cellCount(searchBounds) > 4096 { candidates = Array(objects.indices) }
		else { for cell in cells(searchBounds) { candidates.append(contentsOf: buckets[cell] ?? []) } }
		var seen: Set<Int> = []
		for index in candidates where seen.insert(index).inserted {
			let object = objects[index]
			guard layers.overlaps(object.layers), searchBounds.intersects(object.bounds) else { continue }
			let distance = gap(figure, object.figure)
			if distance <= 0.5 || distance < Double(clearance) - 0.5 { return false }
		}
		return true
	}
}

struct ConnectionRouter {
	var request: ConnectionRoutingRequest
	private let directions = [Point(x: 1, y: 0), Point(x: 1, y: 1), Point(x: 0, y: 1), Point(x: -1, y: 1), Point(x: -1, y: 0), Point(x: -1, y: -1), Point(x: 0, y: -1), Point(x: 1, y: -1)]

	init(_ request: ConnectionRoutingRequest) { self.request = request }

	func plan() throws -> PlannedConnection {
		try Task.checkCancellation()
		guard request.grid > 0, request.width > 0, request.clearance >= request.board.rules.clearance,
			!request.layers.isEmpty, request.layers.allSatisfy(request.board.stack.isSignal), request.viaLimit >= 0, request.maxNodes > 0 else { throw ConnectionRoutingFailure(code: "invalid_rules", visited: 0) }
		if let to = request.to {
			guard request.from.net == to.net else { throw ConnectionRoutingFailure(code: "incompatible_nets", visited: 0) }
			if request.from.id == to.id { return PlannedConnection() }
		} else if !request.from.planeLayers.isEmpty { return PlannedConnection() }
		let obstacles = RoutingObstacles(request)
		let starts = try accesses(request.from, obstacles: obstacles)
		let goals = try request.to.map { try accesses($0, obstacles: obstacles) } ?? [:]
		let targetBounds = request.to.flatMap { Rect.union($0.terminals.map { $0.figure.bounds }) }
		func heuristic(_ point: Point) -> Double {
			guard let bounds = targetBounds else { return 0 }
			let dx = Double(max(bounds.minX - point.x, point.x - bounds.maxX, 0))
			let dy = Double(max(bounds.minY - point.y, point.y - bounds.maxY, 0))
			return (dx * dx + dy * dy).squareRoot()
		}
		var queue = RoutingQueue()
		var costs: [RoutingNode: Double] = [:]
		var previous: [RoutingNode: RoutingNode] = [:]
		var seeds: [RoutingNode: [Trace]] = [:]
		for key in starts.keys.sorted(by: { ($0.layer, $0.point.x, $0.point.y) < ($1.layer, $1.point.x, $1.point.y) }) {
			for path in starts[key]! {
				let heading = path.last.map { direction($0.end - $0.start) } ?? 8
				let node = RoutingNode(point: key.point, layer: key.layer, heading: heading, vias: 0)
				let cost = path.reduce(0) { $0 + Double($1.start.distanceSquared(to: $1.end)).squareRoot() }
				if cost < (costs[node] ?? .infinity) {
					costs[node] = cost
					seeds[node] = path
					queue.push(node, cost: cost, score: cost + heuristic(node.point))
				}
			}
		}
		var visited = 0
		while let item = queue.pop() {
			try Task.checkCancellation()
			let node = item.node
			guard item.cost == costs[node] else { continue }
			guard visited < request.maxNodes else { throw ConnectionRoutingFailure(code: "search_exhausted", visited: visited) }
			visited += 1
			var suffix: [Trace]?
			if let paths = goals[Junction(point: node.point, layer: node.layer)] {
				for path in paths {
					let reversed = path.reversed().map { Trace(start: $0.end, end: $0.start, width: $0.width, layer: $0.layer, net: $0.net) }
					if reversed.first.map({ canTurn(node.heading, direction($0.end - $0.start)) }) ?? true { suffix = reversed; break }
				}
			}
			let plane = request.to == nil && node.vias < request.viaLimit && obstacles.allows(.round(node.point, request.board.rules.viaPad), layers: request.board.stack.top ... request.board.stack.bottom)
			if suffix != nil || plane {
				var result = reconstruct(node, previous: previous, seeds: seeds)
				result.traces.append(contentsOf: suffix ?? [])
				if plane { result.vias.append(Via(at: node.point, net: request.from.net)) }
				result.traces = coalesce(result.traces)
				if result.traces.allSatisfy({ Double($0.start.distanceSquared(to: $0.end)).squareRoot() + 0.5 >= Double(request.board.rules.minTraceLength) }) {
					result.visited = visited
					return result
				}
			}
			func offer(_ next: RoutingNode, extra: Double) {
				let cost = item.cost + extra
				guard cost < (costs[next] ?? .infinity) else { return }
				costs[next] = cost
				previous[next] = node
				queue.push(next, cost: cost, score: cost + heuristic(next.point))
			}
			for (heading, offset) in directions.enumerated() where canTurn(node.heading, heading) {
				let point = node.point + offset * request.grid
				guard obstacles.allows(.segment(node.point, point, request.width), layers: node.layer ... node.layer) else { continue }
				offer(RoutingNode(point: point, layer: node.layer, heading: heading, vias: node.vias), extra: Double(offset.x != 0 && offset.y != 0 ? request.grid : 0) * (2.0.squareRoot() - 1) + Double(request.grid) + (node.heading != heading ? Double(request.grid) * 0.1 : 0))
			}
			if node.vias < request.viaLimit, obstacles.allows(.round(node.point, request.board.rules.viaPad), layers: request.board.stack.top ... request.board.stack.bottom) {
				for layer in request.layers where layer != node.layer { offer(RoutingNode(point: node.point, layer: layer, heading: 8, vias: node.vias + 1), extra: 5_000) }
			}
		}
		throw ConnectionRoutingFailure(code: "no_path", visited: visited)
	}

	private func direction(_ offset: Point) -> Int { directions.firstIndex(of: offset.heading) ?? 8 }
	private func canTurn(_ from: Int, _ to: Int) -> Bool { from == 8 || to == 8 || min(abs(from - to), 8 - abs(from - to)) <= 1 }

	private func accesses(_ island: CopperIsland, obstacles: RoutingObstacles) throws -> [Junction: [[Trace]]] {
		var result: [Junction: [[Trace]]] = [:]
		for terminal in island.terminals {
			try Task.checkCancellation()
			var anchors = terminal.points
			if case let .segment(start, end, _) = terminal.figure {
				anchors += (request.to?.points ?? request.from.points).map { nearest([start, end], to: $0) }
			}
			for anchor in Set(anchors).sorted(by: Point.order) {
				let snapped = anchor.snapped(to: request.grid)
				for x in -2 ... 2 {
					for y in -2 ... 2 {
						let point = snapped + Point(x: x, y: y) * request.grid
						guard result.count < request.maxNodes * 8 else { throw ConnectionRoutingFailure(code: "search_exhausted", visited: 0) }
						for layer in request.layers where terminal.layers.contains(layer) {
							let key = Junction(point: point, layer: layer)
							if terminal.figure.contains(point), obstacles.allows(.round(point, request.width), layers: layer ... layer) { result[key, default: []].append([]); continue }
							let delta = point - anchor
							let span = min(abs(delta.x), abs(delta.y))
							let diagonal = Point(x: delta.x.signum() * span, y: delta.y.signum() * span)
							for points in [[anchor, anchor + diagonal, point], [anchor, point - diagonal, point]] {
								let path = zip(points, points.dropFirst()).filter { $0 != $1 }.map { Trace(start: $0, end: $1, width: request.width, layer: layer, net: island.net) }
								if path.allSatisfy({ obstacles.allows(.segment($0.start, $0.end, request.width), layers: layer ... layer) }) { result[key, default: []].append(path) }
							}
						}
					}
				}
			}
		}
		return result
	}

	private func reconstruct(_ end: RoutingNode, previous: [RoutingNode: RoutingNode], seeds: [RoutingNode: [Trace]]) -> PlannedConnection {
		var node = end
		var traces: [Trace] = [], vias: [Via] = []
		while let parent = previous[node] {
			if parent.layer == node.layer { traces.append(Trace(start: parent.point, end: node.point, width: request.width, layer: node.layer, net: request.from.net)) }
			else { vias.append(Via(at: node.point, net: request.from.net)) }
			node = parent
		}
		return PlannedConnection(traces: (seeds[node] ?? []) + traces.reversed(), vias: Array(vias.reversed()))
	}

	private func coalesce(_ traces: [Trace]) -> [Trace] {
		var result: [Trace] = []
		for trace in traces {
			if let last = result.last, last.layer == trace.layer, last.end == trace.start, (last.end - last.start).heading == (trace.end - trace.start).heading {
				result[result.count - 1].end = trace.end
			} else { result.append(trace) }
		}
		return result
	}
}
