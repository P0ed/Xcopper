import simd

/// One shade's worth of the model, cut into the triangles a renderer takes.
/// Everything painted the same is gathered into a single surface, so a board of
/// a thousand traces is a handful of things to draw rather than a thousand.
/// What the shade comes back as is settled when the board is drawn rather than
/// when it is cut, so a change of mask repaints these rather than rebuilding
/// them.
struct Surface {
	var shade: Shade
	/// Three corners to a triangle. A board is flat faces meeting at hard
	/// edges and no corner is ever shared between two of them, so each carries
	/// the normal of the one face it belongs to.
	var corners: [V3] = []
	var normals: [V3] = []
}

extension Piece {

	/// How far one level of the stack stands over the next. Painting back to
	/// front put the copper over the mask by drawing it later, which a renderer
	/// keeping depth cannot do; the levels are lifted a couple of microns apart
	/// instead, which stands the copper off the laminate by about the thickness
	/// of the foil itself and is under anything the eye, or the fab, would call
	/// a gap.
	static let step = 0.002

	/// The lift this piece's level carries: up over the top face and down under
	/// the bottom one, since a level is signed by the side it belongs to
	var lift: V3 { V3(x: 0.0, y: 0.0, z: Double(level) * Piece.step) }
}

extension Model {

	/// The model gathered by shade and cut into triangles
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

/// Cuts a flat loop, and whatever is punched out of it, into triangles, three
/// corners to each.
///
/// A hole cannot be handed to a renderer the way it is handed to a fill, which
/// takes an outline and reads the hole through it. Each one is first cut open
/// to the loop around it and walked out and back along that cut, which leaves a
/// single loop with nothing punched out of it, and ears are then clipped off
/// what remains until a triangle is all there is left.
func triangulate(_ loop: [V3], holes: [[V3]], facing normal: V3) -> [V3] {
	guard loop.count >= 3 else { return [] }
	let plane = Plane(facing: normal)

	var corners = loop
	var flat = loop.map(plane.flatten)
	var punched: [[Int]] = []

	for hole in holes where hole.count >= 3 {
		let punch = hole.map(plane.flatten)
		// A drill hanging over the edge of the face is not a hole in it. Cutting
		// the face open to one would leave the pieces overlapping, so the face
		// closes over it instead and the bad data shows as the mistake it is.
		guard punch.allSatisfy({ corner in within(flat, loop.indices, corner) }) else { continue }

		let indices = Array(corners.count ..< corners.count + hole.count)
		corners.append(contentsOf: hole)
		flat.append(contentsOf: punch)
		// A hole is wound the way the face it is punched through is. Walked the
		// other way about, the two close into one loop that never crosses
		// itself, which is the only kind ears can be clipped off.
		punched.append(area(of: indices, flat) > 0.0 ? indices.reversed() : indices)
	}

	var ring = Ring(flat, bridges: punched.count)
	let outline = ring.link(Array(loop.indices))
	// Rightmost hole first, since a cut runs out to the right: a hole let in
	// later never has to reach across one already let in.
	for hole in punched.sorted(by: { rightmost($0, flat) > rightmost($1, flat) }) {
		ring.cut(hole)
	}
	return ring.clipped(from: outline).map { index in corners[index] }
}

/// The two directions a face lies flat along, turned so that the face reads
/// counter clockwise in them. Flattening onto its own plane is what tells a
/// hole from the outline around it: in space the two are wound the same way,
/// and only a signed area, which wants two dimensions rather than three, has
/// anything to say about which is which.
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

// MARK: the loop being cut

/// The loop being cut, held as nodes linked into a ring rather than as an array
/// of them. Letting a hole in and taking an ear off are then a matter of
/// relinking two or three nodes, where an array would carry everything after
/// them along, and a corner the loop is cut to twice is two nodes standing for
/// the one corner.
///
/// The ring also keeps track of where its corners lie and which of its edges
/// cross which band of the face. Both of the questions this asks over and over
/// — what stands inside this small triangle, and what does a cut run into on
/// its way out — are about one patch of the face at a time, and a board face is
/// mostly small drills a long way apart, so filing them is the difference
/// between a handful of corners to try and every corner there is.
///
/// A loop with few corners in it is walked instead. Filing costs more than it
/// saves there, and most of a board is exactly that: every trace, every wall of
/// every part, every pad with one drill through it.
private struct Ring {
	/// One corner of the face, and the two it is linked between. A node an ear
	/// has taken off is gone but still filed, so it has to be passed over.
	private struct Node {
		var corner: Int
		var next: Int
		var previous: Int
		var gone = false
	}

	private var nodes: [Node] = []
	/// How many nodes are still in the ring
	private(set) var count = 0

	private let flat: [SIMD2<Double>]
	/// Where the corners stand and which edges cross which band, on a face with
	/// enough corners to be worth the filing
	private var patches: Patches?
	private var bands: Bands?
	/// Where a walk of the ring starts, which is the last corner clipping left
	/// off at
	private var head = 0

	/// How many corners a face has to have before filing them pays for itself
	private static let worthFiling = 64

	init(_ flat: [SIMD2<Double>], bridges: Int) {
		self.flat = flat
		// Every corner of the face, and the two a cut leaves standing twice
		nodes.reserveCapacity(flat.count + 2 * bridges)
		guard flat.count > Ring.worthFiling else { return }
		patches = Patches(covering: flat)
		bands = Bands(covering: flat)
	}

	private func at(_ node: Int) -> SIMD2<Double> { flat[nodes[node].corner] }

	/// Every node of the ring, walked from wherever it was last left
	private func all(_ body: (Int) -> Void) {
		var node = head
		for _ in 0 ..< count {
			body(node)
			node = nodes[node].next
		}
	}

	/// Links a loop of corners into a ring of its own, returning the node it
	/// starts at
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

	/// Files the edge a node leaves along, which is what a ray cast out of a
	/// hole is tried against
	private mutating func file(edgeLeaving node: Int) {
		let (from, to) = (at(node), at(nodes[node].next))
		bands?.file(node, from: from, to: to)
	}

	/// Cuts a hole open to the loop around it, leaving one loop where there were
	/// two. The cut leaves the corner of the hole that reaches furthest right
	/// for the corner of the loop it can see, and is walked out along the hole
	/// and back again, so the seam has no width and closes behind itself.
	///
	/// A hole that cannot see out of the loop it is punched through — one that
	/// is not inside it at all — is left where it is and the face closes over it.
	mutating func cut(_ hole: [Int]) {
		guard let opening = hole.indices.max(by: { flat[hole[$0]].x < flat[hole[$1]].x }),
			let seam = seam(from: flat[hole[opening]])
		else { return }

		let mouth = link(Array(hole[opening...] + hole[..<opening]))
		bridge(mouth, to: seam)
	}

	/// The corner of the loop a cut leaving `mouth` can reach. A ray cast out to
	/// the right meets the loop at the first edge that spans the mouth's height,
	/// and the far end of that edge is in plain sight of the mouth — unless a
	/// corner the loop turns back on stands in the wedge between the two, in
	/// which case the cut makes for whichever of those lies nearest the ray,
	/// which nothing can stand in front of either.
	private func seam(from mouth: SIMD2<Double>) -> Int? {
		var nearest = Double.infinity
		var hit: Int?

		let met = { (node: Int) in
			let (a, b) = (self.at(node), self.at(nodes[node].next))
			// Counted half open, so a ray leaving level with a corner crosses
			// the one edge either side of it rather than both or neither
			guard (a.y > mouth.y) != (b.y > mouth.y) else { return }
			let x = a.x + (mouth.y - a.y) / (b.y - a.y) * (b.x - a.x)
			guard x >= mouth.x, x < nearest else { return }
			nearest = x
			hit = a.x > b.x ? node : nodes[node].next
		}
		if let bands { for node in bands.row(at: mouth.y) { met(node) } } else { all(met) }
		guard let hit else { return nil }

		// A corner a cut has already been made to stands in the ring more than
		// once, once for each wedge of the face it is still open on, and only
		// the one whose wedge this seam sets off into can carry it
		let reached = opening(at: hit, towards: mouth)
		let toward = at(reached)
		let ray = SIMD2(nearest, mouth.y)
		let turn = cross(mouth, ray, toward)
		// The edge the ray met head on leaves no wedge for anything to stand in
		guard turn != 0.0 else { return reached }

		let (a, b, c) = turn > 0.0 ? (mouth, ray, toward) : (mouth, toward, ray)
		var seam = reached
		var tightest = slope(from: mouth, to: toward)
		var closest = toward.x - mouth.x

		let consider = { (node: Int) in
			// Counted to the edge of that wedge and not just the inside of it:
			// drills lined up in a row share a coordinate, so the corners of one
			// stand exactly on the ray cast out of the next and are in the way
			guard node != reached, self.reflex(node), self.opens(node, towards: mouth),
				touching(self.at(node), a, b, c)
			else { return }

			let corner = self.at(node)
			let leaning = slope(from: mouth, to: corner)
			let reach = corner.x - mouth.x
			// The flattest corner, and of two equally flat — a row of drills
			// leaves the ray running through several — the nearest, since a
			// seam reaching past one of them would cut across it
			guard leaning < tightest || (leaning == tightest && reach < closest) else { return }
			tightest = leaning
			closest = reach
			seam = node
		}
		if let patches { patches.walk(covering: a, b, c, consider) } else { all(consider) }
		return seam
	}

	/// Which of the nodes standing at one corner a seam can leave from. A cut
	/// already made to that corner left it standing in the ring twice, with a
	/// wedge of the face on either side of the seam it carries, and the ray
	/// that found the corner has nothing to say about which of the two the
	/// mouth lies in.
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

	/// Whether the loop opens towards a point at one of its corners. The two
	/// edges meeting there leave a wedge of the face behind them, and a cut can
	/// only leave into that wedge.
	private func opens(_ node: Int, towards point: SIMD2<Double>) -> Bool {
		let corner = at(node)
		let back = at(nodes[node].previous) - corner
		let on = at(nodes[node].next) - corner
		let into = point - corner

		func turn(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { a.x * b.y - a.y * b.x }
		// A corner the face turns back on leaves the wider wedge of the two
		return turn(on, back) > 0.0
			? turn(on, into) > 0.0 && turn(into, back) > 0.0
			: turn(on, into) > 0.0 || turn(into, back) > 0.0
	}

	/// Whether the loop turns back on itself at a corner, which is the only kind
	/// a cut can be shut in behind
	private func reflex(_ node: Int) -> Bool {
		cross(at(nodes[node].previous), at(node), at(nodes[node].next)) <= 0.0
	}

	/// Walks the hole out from its mouth and back again, which leaves the two
	/// loops as one. Both ends of the seam stand in the ring twice, once for
	/// the way out and once for the way back.
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

	/// Another node standing for the same corner, which is what a seam with no
	/// width is made of
	private mutating func copy(_ node: Int) -> Int {
		let made = nodes.count
		nodes.append(Node(corner: nodes[node].corner, next: made, previous: made))
		let point = at(node)
		patches?.file(made, at: point)
		return made
	}

	// MARK: clipping

	/// Clips the loop down into triangles. A corner whose two edges cut off a
	/// triangle that lies inside the loop and holds no other corner of it is an
	/// ear: taking it off leaves a loop of the same shape with one corner fewer,
	/// and there is one to take until only a triangle is left.
	mutating func clipped(from start: Int) -> [Int] {
		var triangles: [Int] = []
		guard count >= 3 else { return triangles }
		triangles.reserveCapacity((count - 2) * 3)
		head = start

		while count > 3 {
			let apex = ear(from: head)
			let before = nodes[apex].previous
			let after = nodes[apex].next

			// The seam a cut left behind is a corner with no width, and a
			// triangle with no area is nothing to draw
			if cross(at(before), at(apex), at(after)) > 0.0 {
				triangles.append(contentsOf: [nodes[before].corner, nodes[apex].corner, nodes[after].corner])
			}
			// Carrying on from the corner before the one just taken off, since
			// taking a corner off can leave its neighbour an ear
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

	/// The corner to take off next, looked for from `start` round the loop. An
	/// ear where the loop has one, and failing that whichever corner cuts off
	/// the most: a loop cut about until it crosses itself has no ear left to
	/// find, and taking that corner off at least leaves one corner fewer to try.
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

	/// Whether the triangle three corners in a row cut off holds no other corner
	/// of the loop, which is what makes it an ear. The corners standing in the
	/// patch of the face it covers are the only ones that can be in it, unless
	/// the ear has grown wider than the loop is long, when walking what is left
	/// of the loop is the shorter way round.
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

	/// Whether a corner stands in the way of an ear. Only a corner the loop
	/// turns back on can: one it turns about is inside the ear only where a
	/// reflex one is too, and the seam a cut left behind is nothing but corners
	/// the loop turns back on.
	///
	/// Counted to the edge of the ear and not just the inside of it. Drills
	/// lined up on a board share a coordinate, so a corner of one stands
	/// exactly on the ear taken off another, and an ear clipped over it folds
	/// the face across the drill between them.
	private func held(
		_ node: Int,
		_ a: SIMD2<Double>,
		_ b: SIMD2<Double>,
		_ c: SIMD2<Double>
	) -> Bool {
		touching(at(node), a, b, c) && reflex(node)
	}
}

// MARK: filing the face

/// Where the corners of a face lie, filed by the square of it they fall in. A
/// cut and an ear both have to know what stands inside one small patch of the
/// face, and asking the squares that patch covers is a handful of corners where
/// asking the loop is every corner there is.
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
		// A couple of corners to a square, which is fine enough that a drill
		// falls in one or two of them and coarse enough to stay small
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

	/// How many squares the triangle these three corners make covers, which is
	/// what asking after it costs
	func squares(covering a: SIMD2<Double>, _ b: SIMD2<Double>, _ c: SIMD2<Double>) -> Int {
		let (columns, rows) = span(of: a, b, c)
		return columns.count * rows.count
	}

	/// Hands over every corner filed under the square a point falls in, which is
	/// all of the ones standing on it and some of the ones near it
	func walk(at point: SIMD2<Double>, _ body: (Int) -> Void) {
		let (x, y) = square(of: point)
		for node in cells[y * across + x] { body(node) }
	}

	/// Hands over every corner filed under a square the triangle reaches, which
	/// is all of the ones inside it and some of the ones around it
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

/// The edges of a loop filed by the band of the face they cross. A cut runs out
/// to the right from a hole, and the only edges that can be in its way are the
/// ones that reach its height.
///
/// An edge is filed under the node it leaves, so what is filed follows the loop
/// as it is relinked; a band an edge no longer crosses costs it a test it fails,
/// which is cheaper than keeping the filing exact.
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

// MARK: flat geometry

/// Twice the area a loop covers, positive where it winds counter clockwise
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

/// Whether a point falls inside a loop, counted off a ray cast out of it: it
/// leaves the loop as many times as it enters, so an odd number of crossings
/// means the ray started inside.
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

/// How far right a loop reaches, which is where a cut out of it leaves from
private func rightmost(_ ring: [Int], _ flat: [SIMD2<Double>]) -> Double {
	ring.map { index in flat[index].x }.max() ?? 0.0
}

/// How steeply one point stands off another, which is how a cut picks between
/// the corners it could make for: the flattest is the one nearest the ray it
/// was cast along
private func slope(from: SIMD2<Double>, to point: SIMD2<Double>) -> Double {
	abs(point.y - from.y) / max(point.x - from.x, 1e-12)
}

/// Twice the area of the triangle `abc`, positive where it winds counter
/// clockwise
private func cross(_ a: SIMD2<Double>, _ b: SIMD2<Double>, _ c: SIMD2<Double>) -> Double {
	(b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
}

/// Whether a point falls within the triangle `abc` or anywhere on its edge,
/// which winds counter clockwise
private func touching(
	_ point: SIMD2<Double>,
	_ a: SIMD2<Double>,
	_ b: SIMD2<Double>,
	_ c: SIMD2<Double>
) -> Bool {
	cross(a, b, point) >= 0.0 && cross(b, c, point) >= 0.0 && cross(c, a, point) >= 0.0
}
