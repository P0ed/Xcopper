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
	let outline = loop.map(plane.flatten)
	let contours = [loop] + holes.filter { hole in
		hole.count >= 3 && hole.allSatisfy { within(outline, plane.flatten($0)) }
	}
	var edges: [SweepEdge] = []
	var stops: Set<Double> = []

	for (index, contour) in contours.enumerated() {
		let flat = contour.map(plane.flatten)
		let area = flat.indices.reduce(0.0) { sum, index in
			let a = flat[index]
			let b = flat[(index + 1) % flat.count]
			return sum + a.x * b.y - b.x * a.y
		}
		guard area != 0.0 else { continue }
		let winding = (area > 0.0 ? 1 : -1) * (index == 0 ? 1 : -1)
		for index in flat.indices {
			let next = (index + 1) % flat.count
			let a = flat[index]
			let b = flat[next]
			stops.insert(a.x)
			guard a.x != b.x else { continue }
			let forward = a.x < b.x
			edges.append(SweepEdge(
				from: forward ? contour[index] : contour[next],
				to: forward ? contour[next] : contour[index],
				start: forward ? a : b,
				end: forward ? b : a,
				winding: forward ? winding : -winding
			))
		}
	}

	edges.sort { $0.start.x < $1.start.x }
	let cuts = stops.sorted()
	var active: [SweepEdge] = []
	var next = 0
	var triangles: [V3] = []

	func add(_ a: V3, _ b: V3, _ c: V3) {
		guard (b - a).cross(c - a).dot(normal) > 0.0 else { return }
		triangles.append(contentsOf: [a, b, c])
	}

	for (left, right) in zip(cuts, cuts.dropFirst()) {
		active.removeAll { $0.end.x <= left }
		while next < edges.count, edges[next].start.x <= left {
			active.append(edges[next])
			next += 1
		}
		let middle = left + (right - left) / 2.0
		active.sort { $0.height(at: middle) < $1.height(at: middle) }
		var depth = 0
		var lower: SweepEdge?

		for edge in active {
			let inside = depth > 0
			depth += edge.winding
			if !inside && depth > 0 {
				lower = edge
			} else if inside && depth <= 0, let lower {
				let a = lower.point(at: left)
				let b = lower.point(at: right)
				let c = edge.point(at: right)
				let d = edge.point(at: left)
				add(a, b, c)
				add(a, c, d)
			}
		}
	}
	return triangles
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

private struct SweepEdge {
	var from: V3
	var to: V3
	var start: SIMD2<Double>
	var end: SIMD2<Double>
	var winding: Int

	func height(at x: Double) -> Double {
		start.y + (end.y - start.y) * ((x - start.x) / (end.x - start.x))
	}

	func point(at x: Double) -> V3 {
		if x == start.x { return from }
		if x == end.x { return to }
		return from + (to - from) * ((x - start.x) / (end.x - start.x))
	}
}

private func within(_ loop: [SIMD2<Double>], _ point: SIMD2<Double>) -> Bool {
	var inside = false
	var previous = loop[loop.count - 1]

	for corner in loop {
		if (corner.y > point.y) != (previous.y > point.y) {
			let along = (point.y - corner.y) / (previous.y - corner.y)
			if corner.x + along * (previous.x - corner.x) > point.x { inside.toggle() }
		}
		previous = corner
	}
	return inside
}
