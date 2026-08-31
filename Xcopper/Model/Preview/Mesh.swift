import simd

/// One colour's worth of the model, cut into the triangles a renderer takes.
/// Everything painted in one colour is gathered into a single surface, so a
/// board of a thousand traces is a handful of things to draw rather than a
/// thousand.
struct Surface {
	var color: RGBA
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

	/// The model gathered by colour and cut into triangles
	var surfaces: [Surface] {
		var index: [RGBA: Int] = [:]
		var surfaces: [Surface] = []

		for piece in pieces {
			let found = index[piece.color] ?? surfaces.count
			if found == surfaces.count {
				index[piece.color] = found
				surfaces.append(Surface(color: piece.color))
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

		corners.append(contentsOf: triangles.map { corner in corner + lift })
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
	var ring = Array(loop.indices)
	var punched: [[Int]] = []

	for hole in holes where hole.count >= 3 {
		let indices = Array(corners.count ..< corners.count + hole.count)
		corners.append(contentsOf: hole)
		flat.append(contentsOf: hole.map(plane.flatten))
		// A hole is wound the way the face it is punched through is. Walked the
		// other way about, the two close into one loop that never crosses
		// itself, which is the only kind ears can be clipped off.
		punched.append(area(of: indices, flat) > 0.0 ? indices.reversed() : indices)
	}
	// Rightmost hole first, since a cut runs out to the right: a hole let in
	// later never has to reach across one already let in.
	for hole in punched.sorted(by: { rightmost($0, flat) > rightmost($1, flat) }) {
		cut(hole, into: &ring, flat)
	}
	return clip(ring, flat).map { index in corners[index] }
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

/// How far right a loop reaches, which is where a cut out of it leaves from
private func rightmost(_ ring: [Int], _ flat: [SIMD2<Double>]) -> Double {
	ring.map { index in flat[index].x }.max() ?? 0.0
}

/// Twice the area of the triangle `abc`, positive where it winds counter
/// clockwise
private func cross(_ a: SIMD2<Double>, _ b: SIMD2<Double>, _ c: SIMD2<Double>) -> Double {
	(b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
}

/// Whether a point falls within the triangle `abc`, wound either way. A corner
/// sitting exactly on an edge is not in the way of anything.
private func inside(
	_ point: SIMD2<Double>,
	_ a: SIMD2<Double>,
	_ b: SIMD2<Double>,
	_ c: SIMD2<Double>
) -> Bool {
	let (ab, bc, ca) = (cross(a, b, point), cross(b, c, point), cross(c, a, point))
	return (ab > 0.0 && bc > 0.0 && ca > 0.0) || (ab < 0.0 && bc < 0.0 && ca < 0.0)
}

/// Cuts a hole open to the loop around it, leaving one loop where there were
/// two. The cut runs right from the corner of the hole that reaches furthest
/// that way to a corner of the loop that can see it, and is walked out along
/// the hole and back again, so the seam has no width and closes behind itself.
private func cut(_ hole: [Int], into ring: inout [Int], _ flat: [SIMD2<Double>]) {
	guard let opening = hole.indices.max(by: { flat[hole[$0]].x < flat[hole[$1]].x })
	else { return }
	let mouth = flat[hole[opening]]

	// Straight out to the right until the loop is met. Only an edge the ray
	// passes clean through counts, so a corner is never landed on twice.
	var reach = Double.infinity
	var met: Int?
	for index in ring.indices {
		let a = flat[ring[index]]
		let b = flat[ring[(index + 1) % ring.count]]
		guard (a.y > mouth.y) != (b.y > mouth.y) else { continue }

		let x = a.x + (mouth.y - a.y) / (b.y - a.y) * (b.x - a.x)
		guard x >= mouth.x, x < reach else { continue }
		reach = x
		met = index
	}
	// A hole that is not inside the loop at all has nothing to be cut open to,
	// so it is left where it is and the face closes over it
	guard let met else { return }

	let next = (met + 1) % ring.count
	let far = flat[ring[met]].x > flat[ring[next]].x ? met : next
	let seam = visible(from: mouth, to: SIMD2(reach, mouth.y), past: far, in: ring, flat)

	let walk = Array(hole[opening...] + hole[..<opening])
	ring.insert(contentsOf: walk + [walk[0], ring[seam]], at: seam + 1)
}

/// The corner of the loop a cut can reach without crossing anything. The corner
/// the ray ran past is the one to aim at, unless the loop doubles back into the
/// triangle between the two: a corner jutting in there stands in the way, and
/// the one lying nearest the ray is aimed at instead.
private func visible(
	from mouth: SIMD2<Double>,
	to landing: SIMD2<Double>,
	past far: Int,
	in ring: [Int],
	_ flat: [SIMD2<Double>]
) -> Int {
	var seam = far
	var nearest = -Double.infinity

	for index in ring.indices where index != far {
		let corner = flat[ring[index]]
		let before = flat[ring[(index + ring.count - 1) % ring.count]]
		let after = flat[ring[(index + 1) % ring.count]]

		// Only a corner the loop turns back on can stand in the way
		guard cross(before, corner, after) <= 0.0 else { continue }
		guard inside(corner, mouth, landing, flat[ring[far]]) else { continue }

		let offset = corner - mouth
		let along = offset.x / max((offset.x * offset.x + offset.y * offset.y).squareRoot(), 1e-12)
		if along > nearest {
			nearest = along
			seam = index
		}
	}
	return seam
}

/// Clips a loop down into triangles. A corner whose two edges cut off a
/// triangle that lies inside the loop and holds no other corner of it is an
/// ear: taking it off leaves a loop of the same shape with one corner fewer,
/// and there is one to take until only a triangle is left.
private func clip(_ loop: [Int], _ flat: [SIMD2<Double>]) -> [Int] {
	var ring = loop
	var triangles: [Int] = []
	triangles.reserveCapacity((ring.count - 2) * 3)
	var from = 0

	while ring.count > 3 {
		let corner = ear(in: ring, from: from, flat)
		let before = ring[(corner + ring.count - 1) % ring.count]
		let after = ring[(corner + 1) % ring.count]

		// The seam a cut left behind is a corner with no width, and a triangle
		// with no area is nothing to draw
		if cross(flat[before], flat[ring[corner]], flat[after]) > 0.0 {
			triangles.append(contentsOf: [before, ring[corner], after])
		}
		ring.remove(at: corner)
		from = max(0, corner - 1)
	}
	if cross(flat[ring[0]], flat[ring[1]], flat[ring[2]]) > 0.0 {
		triangles.append(contentsOf: ring)
	}
	return triangles
}

/// The corner to take off next, looked for from `from` round the loop. An ear
/// where the loop has one, and failing that whichever corner cuts off the most:
/// a loop cut about until it crosses itself has no ear left to find, and taking
/// that corner off at least leaves one corner fewer to try.
private func ear(in ring: [Int], from: Int, _ flat: [SIMD2<Double>]) -> Int {
	var widest = -Double.infinity
	var most = 0

	for offset in ring.indices {
		let corner = (from + offset) % ring.count
		let previous = (corner + ring.count - 1) % ring.count
		let next = (corner + 1) % ring.count
		let (before, apex, after) = (flat[ring[previous]], flat[ring[corner]], flat[ring[next]])

		let turn = cross(before, apex, after)
		if turn > widest {
			widest = turn
			most = corner
		}
		guard turn > 0.0 else { continue }

		let clear = ring.indices.allSatisfy { other in
			other == previous || other == corner || other == next
				|| !inside(flat[ring[other]], before, apex, after)
		}
		if clear { return corner }
	}
	return most
}
