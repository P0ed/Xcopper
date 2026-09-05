import simd

struct Surface {
	var shade: Shade
	var corners: [V3] = []
	var normals: [V3] = []
}

extension Piece {

	static let step = 0.002

	var lift: V3 { V3(x: 0.0, y: 0.0, z: Double(level) * Piece.step) }
}

extension Model {

	var surfaces: [Surface] {
		var index: [Shade: Int] = [:]
		var surfaces: [Surface] = []

		for piece in pieces {
			let found = index[piece.shade] ?? surfaces.count
			if found == surfaces.count {
				index[piece.shade] = found
				surfaces.append(Surface(shade: piece.shade))
			}
			surfaces[found].add(piece)
		}
		return surfaces
	}
}

extension Surface {

	mutating func add(_ piece: Piece) {
		let lift = piece.lift
		let triangles = triangulate(piece.loop, holes: piece.holes, facing: piece.normal)

		for corner in triangles { corners.append(corner + lift) }
		normals.append(contentsOf: repeatElement(piece.normal, count: triangles.count))
	}
}

func triangulate(_ loop: [V3], holes: [[V3]], facing normal: V3) -> [V3] {
	guard loop.count >= 3 else { return [] }
	let plane = Plane(facing: normal)

	var corners = loop
	var flat = loop.map(plane.flatten)
	var punched: [[Int]] = []

	for hole in holes where hole.count >= 3 {
		let punch = hole.map(plane.flatten)
		guard punch.allSatisfy({ corner in within(flat, loop.indices, corner) }) else { continue }

		let indices = Array(corners.count ..< corners.count + hole.count)
		corners.append(contentsOf: hole)
		flat.append(contentsOf: punch)
		punched.append(area(of: indices, flat) > 0.0 ? indices.reversed() : indices)
	}

	var ring = Ring(flat, bridges: punched.count)
	let outline = ring.link(Array(loop.indices))
	for hole in punched.sorted(by: { rightmost($0, flat) > rightmost($1, flat) }) {
		ring.cut(hole)
	}
	return ring.clipped(from: outline).map { index in corners[index] }
}

private struct Plane {
	var u: V3
	var v: V3

	init(facing normal: V3) {
		let axis = abs(normal.z) < 0.9 ? V3(x: 0.0, y: 0.0, z: 1.0) : V3(x: 1.0, y: 0.0, z: 0.0)
		u = axis.cross(normal).normalized
		v = normal.cross(u)
	}

	func flatten(_ point: V3) -> SIMD2<Double> { SIMD2(point.dot(u), point.dot(v)) }
}

private struct Ring {
	private struct Node {
		var corner: Int
		var next: Int
		var previous: Int
		var gone = false
	}

	private var nodes: [Node] = []
	private(set) var count = 0

	private let flat: [SIMD2<Double>]
	private var patches: Patches?
	private var bands: Bands?
	private var head = 0

	private static let worthFiling = 64

	init(_ flat: [SIMD2<Double>], bridges: Int) {
		self.flat = flat
		nodes.reserveCapacity(flat.count + 2 * bridges)
		guard flat.count > Ring.worthFiling else { return }
		patches = Patches(covering: flat)
		bands = Bands(covering: flat)
	}

	private func at(_ node: Int) -> SIMD2<Double> { flat[nodes[node].corner] }

	private func all(_ body: (Int) -> Void) {
		var node = head
		for _ in 0 ..< count {
			body(node)
			node = nodes[node].next
		}
	}

	mutating func link(_ indices: [Int]) -> Int {
		let first = nodes.count
		let last = first + indices.count - 1

		for (offset, index) in indices.enumerated() {
			let node = first + offset
			nodes.append(Node(
				corner: index,
				next: node == last ? first : node + 1,
				previous: node == first ? last : node - 1
			))
			let point = flat[index]
			patches?.file(node, at: point)
		}
		count += indices.count
		for node in first ... last { file(edgeLeaving: node) }
		return first
	}

	private mutating func file(edgeLeaving node: Int) {
		let (from, to) = (at(node), at(nodes[node].next))
		bands?.file(node, from: from, to: to)
	}

	mutating func cut(_ hole: [Int]) {
		guard let opening = hole.indices.max(by: { flat[hole[$0]].x < flat[hole[$1]].x }),
			let seam = seam(from: flat[hole[opening]])
		else { return }

		let mouth = link(Array(hole[opening...] + hole[..<opening]))
		bridge(mouth, to: seam)
	}

	private func seam(from mouth: SIMD2<Double>) -> Int? {
		var nearest = Double.infinity
		var hit: Int?

		let met = { (node: Int) in
			let (a, b) = (self.at(node), self.at(nodes[node].next))
			guard (a.y > mouth.y) != (b.y > mouth.y) else { return }
			let x = a.x + (mouth.y - a.y) / (b.y - a.y) * (b.x - a.x)
			guard x >= mouth.x, x < nearest else { return }
			nearest = x
			hit = a.x > b.x ? node : nodes[node].next
		}
		if let bands { for node in bands.row(at: mouth.y) { met(node) } } else { all(met) }
		guard let hit else { return nil }

		let reached = opening(at: hit, towards: mouth)
		let toward = at(reached)
		let ray = SIMD2(nearest, mouth.y)
		let turn = cross(mouth, ray, toward)
		guard turn != 0.0 else { return reached }

		let (a, b, c) = turn > 0.0 ? (mouth, ray, toward) : (mouth, toward, ray)
		var seam = reached
		var tightest = slope(from: mouth, to: toward)
		var closest = toward.x - mouth.x

		let consider = { (node: Int) in
			guard node != reached, self.reflex(node), self.opens(node, towards: mouth),
				touching(self.at(node), a, b, c)
			else { return }

			let corner = self.at(node)
			let leaning = slope(from: mouth, to: corner)
			let reach = corner.x - mouth.x
			guard leaning < tightest || (leaning == tightest && reach < closest) else { return }
			tightest = leaning
			closest = reach
			seam = node
		}
		if let patches { patches.walk(covering: a, b, c, consider) } else { all(consider) }
		return seam
	}

	private func opening(at hit: Int, towards mouth: SIMD2<Double>) -> Int {
		guard !opens(hit, towards: mouth) else { return hit }
		var found = hit

		let consider = { (node: Int) in
			guard found == hit, node != hit, nodes[node].corner == nodes[hit].corner,
				self.opens(node, towards: mouth)
			else { return }
			found = node
		}
		if let patches { patches.walk(at: at(hit), consider) } else { all(consider) }
		return found
	}

	private func opens(_ node: Int, towards point: SIMD2<Double>) -> Bool {
		let corner = at(node)
		let back = at(nodes[node].previous) - corner
		let on = at(nodes[node].next) - corner
		let into = point - corner

		func turn(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { a.x * b.y - a.y * b.x }
		return turn(on, back) > 0.0
			? turn(on, into) > 0.0 && turn(into, back) > 0.0
			: turn(on, into) > 0.0 || turn(into, back) > 0.0
	}

	private func reflex(_ node: Int) -> Bool {
		cross(at(nodes[node].previous), at(node), at(nodes[node].next)) <= 0.0
	}

	private mutating func bridge(_ mouth: Int, to seam: Int) {
		let tail = nodes[mouth].previous
		let follow = nodes[seam].next
		let echo = copy(mouth)
		let back = copy(seam)

		nodes[seam].next = mouth
		nodes[mouth].previous = seam
		nodes[tail].next = echo
		nodes[echo].previous = tail
		nodes[echo].next = back
		nodes[back].previous = echo
		nodes[back].next = follow
		nodes[follow].previous = back
		count += 2

		for node in [seam, tail, echo, back] { file(edgeLeaving: node) }
	}

	private mutating func copy(_ node: Int) -> Int {
		let made = nodes.count
		nodes.append(Node(corner: nodes[node].corner, next: made, previous: made))
		let point = at(node)
		patches?.file(made, at: point)
		return made
	}

	mutating func clipped(from start: Int) -> [Int] {
		var triangles: [Int] = []
		guard count >= 3 else { return triangles }
		triangles.reserveCapacity((count - 2) * 3)
		head = start

		while count > 3 {
			let apex = ear(from: head)
			let before = nodes[apex].previous
			let after = nodes[apex].next

			if cross(at(before), at(apex), at(after)) > 0.0 {
				triangles.append(contentsOf: [nodes[before].corner, nodes[apex].corner, nodes[after].corner])
			}
			head = before
			remove(apex)
		}
		let after = nodes[head].next
		if cross(at(head), at(after), at(nodes[after].next)) > 0.0 {
			triangles.append(contentsOf: [
				nodes[head].corner,
				nodes[after].corner,
				nodes[nodes[after].next].corner,
			])
		}
		return triangles
	}

	private mutating func remove(_ node: Int) {
		let (before, after) = (nodes[node].previous, nodes[node].next)
		nodes[before].next = after
		nodes[after].previous = before
		nodes[node].gone = true
		count -= 1
	}

	private func ear(from start: Int) -> Int {
		var widest = -Double.infinity
		var most = start
		var node = start

		for _ in 0 ..< count {
			let (before, after) = (nodes[node].previous, nodes[node].next)
			let turn = cross(at(before), at(node), at(after))

			if turn > widest {
				widest = turn
				most = node
			}
			if turn > 0.0, clear(before, node, after) { return node }
			node = after
		}
		return most
	}

	private func clear(_ before: Int, _ apex: Int, _ after: Int) -> Bool {
		let (a, b, c) = (at(before), at(apex), at(after))

		guard let patches, patches.squares(covering: a, b, c) <= count else {
			var node = nodes[after].next
			while node != before {
				if held(node, a, b, c) { return false }
				node = nodes[node].next
			}
			return true
		}
		var blocked = false
		patches.walk(covering: a, b, c) { node in
			guard !blocked, !nodes[node].gone, node != before, node != apex, node != after
			else { return }
			if held(node, a, b, c) { blocked = true }
		}
		return !blocked
	}

	private func held(
		_ node: Int,
		_ a: SIMD2<Double>,
		_ b: SIMD2<Double>,
		_ c: SIMD2<Double>
	) -> Bool {
		touching(at(node), a, b, c) && reflex(node)
	}
}

private struct Patches {
	private var cells: [[Int]]
	private let origin: SIMD2<Double>
	private let step: SIMD2<Double>
	private let across: Int
	private let down: Int

	init(covering flat: [SIMD2<Double>]) {
		var lower = SIMD2(Double.infinity, Double.infinity)
		var upper = SIMD2(-Double.infinity, -Double.infinity)
		for point in flat {
			lower = simd_min(lower, point)
			upper = simd_max(upper, point)
		}
		let span = simd_max(upper - lower, SIMD2(1e-9, 1e-9))
		let wanted = max(1.0, Double(flat.count) / 2.0)

		across = max(1, Int((wanted * span.x / span.y).squareRoot().rounded()))
		down = max(1, Int(wanted / Double(across)))
		origin = lower
		step = span / SIMD2(Double(across), Double(down))
		cells = Array(repeating: [], count: across * down)
	}

	mutating func file(_ node: Int, at point: SIMD2<Double>) {
		let (x, y) = square(of: point)
		cells[y * across + x].append(node)
	}

	func squares(covering a: SIMD2<Double>, _ b: SIMD2<Double>, _ c: SIMD2<Double>) -> Int {
		let (columns, rows) = span(of: a, b, c)
		return columns.count * rows.count
	}

	func walk(at point: SIMD2<Double>, _ body: (Int) -> Void) {
		let (x, y) = square(of: point)
		for node in cells[y * across + x] { body(node) }
	}

	func walk(
		covering a: SIMD2<Double>,
		_ b: SIMD2<Double>,
		_ c: SIMD2<Double>,
		_ body: (Int) -> Void
	) {
		let (columns, rows) = span(of: a, b, c)
		for row in rows {
			for column in columns {
				for node in cells[row * across + column] { body(node) }
			}
		}
	}

	private func span(
		of a: SIMD2<Double>,
		_ b: SIMD2<Double>,
		_ c: SIMD2<Double>
	) -> (Range<Int>, Range<Int>) {
		let low = square(of: simd_min(a, simd_min(b, c)))
		let high = square(of: simd_max(a, simd_max(b, c)))
		return (low.x ..< high.x + 1, low.y ..< high.y + 1)
	}

	private func square(of point: SIMD2<Double>) -> (x: Int, y: Int) {
		let offset = (point - origin) / step
		return (
			min(max(Int(offset.x), 0), across - 1),
			min(max(Int(offset.y), 0), down - 1)
		)
	}
}

private struct Bands {
	private var rows: [[Int]]
	private let lower: Double
	private let scale: Double

	init(covering flat: [SIMD2<Double>]) {
		var low = Double.infinity
		var high = -Double.infinity
		for point in flat {
			low = min(low, point.y)
			high = max(high, point.y)
		}
		let count = max(1, flat.count / 8)

		rows = Array(repeating: [], count: count)
		lower = low
		scale = Double(count) / max(high - low, 1e-9)
	}

	mutating func file(_ node: Int, from a: SIMD2<Double>, to b: SIMD2<Double>) {
		for row in band(at: min(a.y, b.y)) ... band(at: max(a.y, b.y)) { rows[row].append(node) }
	}

	func row(at y: Double) -> [Int] { rows[band(at: y)] }

	private func band(at y: Double) -> Int {
		min(max(Int((y - lower) * scale), 0), rows.count - 1)
	}
}

private func area(of ring: [Int], _ flat: [SIMD2<Double>]) -> Double {
	var sum = 0.0
	var previous = flat[ring[ring.count - 1]]
	for index in ring {
		let point = flat[index]
		sum += previous.x * point.y - point.x * previous.y
		previous = point
	}
	return sum
}

private func within(_ flat: [SIMD2<Double>], _ loop: Range<Int>, _ point: SIMD2<Double>) -> Bool {
	var inside = false
	var previous = flat[loop.upperBound - 1]

	for index in loop {
		let corner = flat[index]
		if (corner.y > point.y) != (previous.y > point.y) {
			let along = (point.y - corner.y) / (previous.y - corner.y)
			if corner.x + along * (previous.x - corner.x) > point.x { inside.toggle() }
		}
		previous = corner
	}
	return inside
}

private func rightmost(_ ring: [Int], _ flat: [SIMD2<Double>]) -> Double {
	ring.map { index in flat[index].x }.max() ?? 0.0
}

private func slope(from: SIMD2<Double>, to point: SIMD2<Double>) -> Double {
	abs(point.y - from.y) / max(point.x - from.x, 1e-12)
}

private func cross(_ a: SIMD2<Double>, _ b: SIMD2<Double>, _ c: SIMD2<Double>) -> Double {
	(b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
}

private func touching(
	_ point: SIMD2<Double>,
	_ a: SIMD2<Double>,
	_ b: SIMD2<Double>,
	_ c: SIMD2<Double>
) -> Bool {
	cross(a, b, point) >= 0.0 && cross(b, c, point) >= 0.0 && cross(c, a, point) >= 0.0
}
