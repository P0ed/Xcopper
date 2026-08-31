/// One connection the netlist demands but copper does not yet make
struct Rat: Hashable {
	var from: Pt
	var to: Pt
	var net: Net.ID
}

/// Something copper can land on: a pad or a via, with the layers it reaches
private struct Terminal {
	var at: Pt
	var figure: Figure
	var layers: ClosedRange<Int>
	var net: Net.ID
}

private struct Merge {
	private var parent: [Int]

	init(count: Int) { parent = Array(0 ..< count) }

	mutating func find(_ index: Int) -> Int {
		var root = index
		while parent[root] != root { root = parent[root] }
		var walk = index
		while parent[walk] != root {
			let next = parent[walk]
			parent[walk] = root
			walk = next
		}
		return root
	}

	mutating func union(_ a: Int, _ b: Int) {
		let (ra, rb) = (find(a), find(b))
		guard ra != rb else { return }
		parent[ra] = rb
	}
}

extension Board {

	private var terminals: [Terminal] {
		var result: [Terminal] = []

		for footprint in footprints {
			for pad in footprint.placedPads {
				guard let net = pad.net else { continue }
				let layer = footprint.layer(of: pad, in: stack)
				result.append(Terminal(
					at: pad.at,
					figure: pad.figure,
					layers: pad.isThrough ? stack.top ... stack.bottom : layer ... layer,
					net: net
				))
			}
		}
		for via in vias {
			guard let net = via.net else { continue }
			result.append(Terminal(at: via.at, figure: .round(via.at, via.pad), layers: via.span, net: net))
		}
		return result
	}

	/// Connections a shared net implies that copper does not yet satisfy, as a
	/// minimum spanning tree over each net's disconnected islands.
	func ratsnest() -> [Rat] {
		let terminals = terminals
		guard terminals.count > 1 else { return [] }

		var merge = Merge(count: terminals.count + traces.count)

		// Compound pads may use several overlapping copper primitives with the
		// same pin number (for example, a large mounting annulus plus a small
		// wire hole). Treat those primitives as one copper island.
		for index in terminals.indices {
			for other in terminals.indices where other > index {
				let terminal = terminals[index]
				let peer = terminals[other]
				guard terminal.net == peer.net,
					terminal.layers.overlaps(peer.layers),
					terminal.figure.contains(peer.at) || peer.figure.contains(terminal.at)
				else { continue }
				merge.union(index, other)
			}
		}

		// Routing snaps to pad centres, via centres and trace ends, so joining
		// on endpoints alone reproduces the copper faithfully.
		for (index, trace) in traces.enumerated() {
			let node = terminals.count + index

			for (other, terminal) in terminals.enumerated()
			where terminal.layers.contains(trace.layer)
				&& (terminal.figure.contains(trace.start) || terminal.figure.contains(trace.end)) {
				merge.union(node, other)
			}
			for (other, peer) in traces.enumerated()
			where other > index && peer.layer == trace.layer {
				let figure = Figure.segment(peer.start, peer.end, peer.width)
				if figure.contains(trace.start) || figure.contains(trace.end) {
					merge.union(node, terminals.count + other)
				}
			}
		}

		var byNet: [Net.ID: [Int]] = [:]
		for (index, terminal) in terminals.enumerated() {
			byNet[terminal.net, default: []].append(index)
		}

		var rats: [Rat] = []
		for (net, indices) in byNet.sorted(by: { $0.key < $1.key }) {
			var islands: [Int: [Int]] = [:]
			for index in indices { islands[merge.find(index), default: []].append(index) }
			guard islands.count > 1 else { continue }

			var loose = islands.values.sorted { ($0.first ?? 0) < ($1.first ?? 0) }
			var tree = [loose.removeFirst()]

			while !loose.isEmpty {
				var best: (distance: Int, island: Int, rat: Rat)?

				for member in tree {
					for (island, candidate) in loose.enumerated() {
						for here in member {
							for there in candidate {
								let distance = terminals[here].at.distanceSquared(to: terminals[there].at)
								guard distance < (best?.distance ?? Int.max) else { continue }
								best = (
									distance,
									island,
									Rat(from: terminals[here].at, to: terminals[there].at, net: net)
								)
							}
						}
					}
				}
				guard let best else { break }
				rats.append(best.rat)
				tree.append(loose.remove(at: best.island))
			}
		}
		return rats
	}
}
