struct Rat: Hashable {
	var from: Point
	var to: Point
	var net: Net.ID
}

struct Strand: Hashable {
	var at: Point
	var net: Net.ID
}

private struct Terminal {
	var at: Point
	var figure: Figure
	var layers: ClosedRange<Int>
	var net: Net.ID
}

extension Board {

	private var terminals: [Terminal] {
		var result: [Terminal] = []

		for footprint in footprints {
			for trace in footprint.copper(in: stack) {
				guard let net = trace.net else { continue }
				result.append(Terminal(
					at: trace.start,
					figure: .segment(trace.start, trace.end, trace.width),
					layers: trace.layer ... trace.layer,
					net: net
				))
			}
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
			result.append(Terminal(at: via.at, figure: .round(via.at, rules.viaPad), layers: stack.top ... stack.bottom, net: net))
		}
		return result
	}

	private func merged(_ terminals: [Terminal], planes: [Net.ID?]) -> UnionFind<Int> {
		var merge = UnionFind<Int>()

		for (layer, plane) in planes.enumerated() {
			guard let plane else { continue }
			let node = terminals.count + traces.count + layer

			for (index, terminal) in terminals.enumerated()
			where terminal.net == plane && terminal.layers.contains(layer) {
				merge.union(node, index)
			}
		}

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
		return merge
	}

	func ratsnest(planes: [Net.ID?] = []) -> [Rat] {
		let terminals = terminals
		guard terminals.count > 1 else { return [] }
		var merge = merged(terminals, planes: planes)

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

	func stranded(planes: [Net.ID?]) -> [Strand] {
		guard planes.contains(where: { $0 != nil }) else { return [] }
		let terminals = terminals
		guard !terminals.isEmpty else { return [] }
		var merge = merged(terminals, planes: planes)

		var roots: [Net.ID: Set<Int>] = [:]
		for (layer, plane) in planes.enumerated() {
			guard let plane else { continue }
			roots[plane, default: []].insert(merge.find(terminals.count + traces.count + layer))
		}

		var seen: Set<Int> = []
		var found: [Strand] = []
		for (index, terminal) in terminals.enumerated() {
			guard let joined = roots[terminal.net] else { continue }
			let root = merge.find(index)
			guard !joined.contains(root), seen.insert(root).inserted else { continue }
			found.append(Strand(at: terminal.at, net: terminal.net))
		}
		return found
	}
}
