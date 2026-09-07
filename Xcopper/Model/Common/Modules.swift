import Foundation
import Synchronization

final class ModuleProjectionCache: Sendable, Equatable {
	static func == (_: ModuleProjectionCache, _: ModuleProjectionCache) -> Bool { true }

	private let projections = Mutex<[Bool: ModuleProjection]>([:])

	func value(syncNative: Bool, build: () -> ModuleProjection) -> ModuleProjection {
		projections.withLock { values in
			if let cached = values[syncNative] { return cached }
			let projection = build()
			values[syncNative] = projection
			return projection
		}
	}
}

struct ModuleInstance: Equatable, Codable, Identifiable {
	var id = UUID()
	var reference: String
	var filename: String
	var schematicAt: Point = .zero
	var schematicRotation: Rotation = .r0
	var layoutAt: Point = .zero
	var layoutRotation: Rotation = .r0
	var interface: [String] = []
	var size = Size(width: .mm(20), height: .mm(20))
	var layerCount: Int = 2

	var symbol: Symbol {
		var symbol = Symbol.ic(pinNames: interface)
		symbol.reference = reference
		symbol.value = filename
		symbol.at = schematicAt
		symbol.rotation = schematicRotation
		for i in symbol.pins.indices { symbol.pins[i].number = interface[i] }
		return symbol
	}

	func place(_ point: Point) -> Point { point.rotated(layoutRotation) + layoutAt }
	var bounds: Rect { Rect(from: place(.zero), to: place(Point(x: size.width, y: size.height))) }
}

struct ModuleContent: Equatable {
	var board: Board
	var nets: [Net]
	var ports: [String: Net.ID]
}

struct ModuleCache: Equatable {
	var contents: [UUID: ModuleContent] = [:]
	var errors: [UUID: String] = [:]
	var notices: [String] = []
}

struct ModuleProjection {
	var design: Design
	var owners: [Ref: UUID] = [:]
	var symbolOwners: [Schematic.Ref: UUID] = [:]
	var ports: [String: Net.ID] = [:]
	var interfaceError: String?
	var report = Design.Report()

	func owner(_ ref: Ref) -> Ref {
		if case let .pad(index, _) = ref { return owners[.footprint(index)].map(Ref.module) ?? ref }
		return owners[ref].map(Ref.module) ?? ref
	}
	func owner(_ ref: Schematic.Ref) -> Schematic.Ref { symbolOwners[ref].map(Schematic.Ref.module) ?? ref }
	func expanded(_ refs: Set<Ref>) -> Set<Ref> {
		let ids = refs.moduleIDs
		guard !ids.isEmpty else { return refs }
		return refs.union(owners.compactMap { ids.contains($0.value) ? $0.key : nil })
	}
	func expanded(_ refs: Set<Schematic.Ref>) -> Set<Schematic.Ref> {
		let ids = refs.moduleIDs
		guard !ids.isEmpty else { return refs }
		return refs.union(symbolOwners.compactMap { ids.contains($0.value) ? $0.key : nil })
	}
}

extension NetLabel {
	var ioName: String? {
		guard text.hasPrefix("#") else { return nil }
		let name = String(text.dropFirst())
		return name.trimmingWhitespace.isEmpty ? nil : name
	}
}

private let supplyNames: Set<String> = ["GND", "VCC", "VEE"]

private func moduleNetID(_ key: String) -> Int {
	let hash = key.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
	return -Int(hash & 0x3fff_ffff_ffff_ffff) - 1
}

extension Design {
	var moduleErrors: [String] {
		modules.compactMap { module in
			moduleStatus(module.id).map { "\(module.reference) (\(module.filename)): \($0)" }
		}
	}

	func moduleStatus(_ id: UUID) -> String? {
		if let error = moduleCache.errors[id] { return error }
		guard let content = moduleCache.contents[id] else { return "Unresolved. Use Reload Modules to locate the source." }
		return content.board.stack.count > board.stack.count ? "Source needs more copper layers. Increase the board stack and reload." : nil
	}

	func canRestack(_ stack: Stack) -> Bool {
		modules.allSatisfy { max($0.layerCount, moduleCache.contents[$0.id]?.board.stack.count ?? 0) <= stack.count }
	}

	var resolved: Design { moduleProjection().design }

	func buildModuleProjection(syncNative: Bool) -> ModuleProjection {
		var result = ModuleProjection(design: self)
		result.design.modules = []
		result.design.moduleCache = ModuleCache()
		var nets = Dictionary(nets.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
		var portsBySymbol: [Int: [String: Int]] = [:]
		var merge = UnionFind<Int>()
		let netIDsByName = Dictionary(self.nets.map { ($0.name, $0.id) }, uniquingKeysWith: { a, _ in a })
		func global(_ name: String) -> Int? {
			guard supplyNames.contains(name) else { return nil }
			let id = netIDsByName[name] ?? moduleNetID("power/\(name)")
			nets[id] = name
			return id
		}
		for module in modules {
			let symbolIndex = result.design.schematic.symbols.count
			result.symbolOwners[.symbol(symbolIndex)] = module.id
			let status = moduleStatus(module.id)
			var symbol = module.symbol
			if status != nil { symbol.value = "⚠ Unresolved: " + module.filename }
			result.design.schematic.symbols.append(symbol)
			guard status == nil, let content = moduleCache.contents[module.id] else { continue }
			var mapping: [Int: Int] = [:]
			for net in content.nets {
				let id = global(net.name) ?? moduleNetID("\(module.id)/\(net.id)")
				mapping[net.id] = id
				if nets[id] == nil { nets[id] = "\(module.reference)/\(net.name)" }
			}
			portsBySymbol[symbolIndex] = content.ports.mapValues { mapping[$0]! }
			var imported = content.board
			imported.restack(board.stack)
			imported.mapNets { $0.flatMap { mapping[$0] } }
			for var trace in imported.traces {
				trace.start = module.place(trace.start); trace.end = module.place(trace.end)
				result.owners[.trace(result.design.board.traces.count)] = module.id
				result.design.board.traces.append(trace)
			}
			for var via in imported.vias {
				via.at = module.place(via.at)
				result.owners[.via(result.design.board.vias.count)] = module.id
				result.design.board.vias.append(via)
			}
			for var hole in imported.holes {
				hole.at = module.place(hole.at)
				result.owners[.hole(result.design.board.holes.count)] = module.id
				result.design.board.holes.append(hole)
			}
			for var footprint in imported.footprints {
				footprint.at = module.place(footprint.at)
				footprint.rotation = footprint.rotation.adding(module.layoutRotation)
				footprint.reference = "\(module.reference)/\(footprint.reference)"
				result.owners[.footprint(result.design.board.footprints.count)] = module.id
				result.design.board.footprints.append(footprint)
			}
		}

		var electrical = result.design.schematic
		electrical.labels.removeAll { $0.ioName != nil }
		electrical.labels += schematic.labels.filter { $0.ioName != nil }.map { NetLabel(at: $0.at, text: "") }
		let netlist = Netlist(electrical)
		var footprintsByReference: [String: [Int]] = [:]
		for i in board.footprints.indices { footprintsByReference[board.footprints[i].reference, default: []].append(i) }
		var ioNamesByPoint: [Point: [String]] = [:]
		for label in schematic.labels { if let name = label.ioName { ioNamesByPoint[label.at, default: []].append(name) } }
		var pointNets: [Point: Int] = [:]
		var assignments: [(Int, Int, Int)] = []
		var wired: Set<String> = []
		for group in netlist.groups {
			let nodes = group.nodes.sorted { ($0.symbol, $0.pin) < ($1.symbol, $1.pin) }
			let active = nodes.count > 1 || group.name != nil || group.points.contains { ioNamesByPoint[$0] != nil }
			var connected: [Int] = []
			var pads: [(Int, Int)] = []
			for node in nodes {
				let symbol = electrical.symbols[node.symbol]
				let pin = symbol.pins[node.pin].number
				if let id = portsBySymbol[node.symbol]?[pin] {
					connected.append(id)
					if active { result.report.assigned += 1 }
					continue
				}
				guard node.symbol < schematic.symbols.count else { continue }
				let matches = footprintsByReference[symbol.reference] ?? []
				if active {
					wired.insert(symbol.reference)
					if matches.isEmpty {
						result.report.missingFootprints.append(symbol.reference)
					} else if !matches.contains(where: { board.footprints[$0].pads.contains { $0.name == pin } }) {
						result.report.missingPins.append("\(symbol.reference).\(pin)")
					}
				}
				for i in matches {
					for j in board.footprints[i].pads.indices where board.footprints[i].pads[j].name == pin {
						pads.append((i, j))
						if let id = board.footprints[i].pads[j].net { connected.append(id) }
					}
				}
			}
			if !active && connected.isEmpty { continue }
			let key = nodes.isEmpty ? group.points.flatMap { ioNamesByPoint[$0] ?? [] }.sorted().joined(separator: "/") : group.pinNames(in: electrical).joined(separator: "/")
			let fallback = moduleNetID("group/\(key.isEmpty ? String(describing: group.points.sorted(by: Point.order)) : key)")
			let named = group.name.map { name in netIDsByName[name] ?? moduleNetID("named/\(name)") }
			let power = connected.first { id in nets[id].map(supplyNames.contains) ?? false }
			let id = named ?? power ?? connected.first ?? fallback
			if nets[id] == nil { nets[id] = group.name ?? "N$\(key.isEmpty ? String(-fallback) : key)" }
			for other in connected { merge.union(other, id) }
			for point in group.points { pointNets[point] = id }
			if syncNative, active {
				result.report.assigned += pads.count
				for (i, j) in pads { assignments.append((i, j, id)) }
			}
		}
		for (i, j, id) in assignments { result.design.board.footprints[i].pads[j].net = id }
		result.design.board.mapNets { $0.map { merge.find($0) } }
		for label in schematic.labels {
			guard let name = label.ioName, let id = pointNets[label.at].map({ merge.find($0) }) else { continue }
			if let existing = result.ports[name], existing != id {
				result.interfaceError = "Ambiguous #\(name): repeated labels resolve to different nets. Connect them to the same net and reload."
			}
			result.ports[name] = id
		}
		result.report.missingFootprints = Set(result.report.missingFootprints).sorted()
		result.report.missingPins.sort()
		result.report.extraFootprints = board.footprints.map(\.reference).filter { !wired.contains($0) }.sorted()
		let nativeIDs = Set(self.nets.map(\.id))
		result.design.nets = nets.keys.sorted().filter { nativeIDs.contains($0) || merge.find($0) == $0 }.map { Net(id: $0, name: nets[$0]!) }
		result.report.created = result.design.nets.filter { !nativeIDs.contains($0.id) }.map(\.name)
		return result
	}
}

struct ModuleResolver {
	var folder: URL
	var read: (URL) throws -> Data = { try Data(contentsOf: $0) }
	private var loaded: [URL: Design] = [:]
	private var contents: [URL: ModuleContent] = [:]

	init(folder: URL, read: @escaping (URL) throws -> Data = { try Data(contentsOf: $0) }) {
		self.folder = folder.resolvingSymlinksInPath().standardizedFileURL
		self.read = read
	}

	func url(for filename: String) throws -> URL {
		guard !filename.isEmpty, !filename.contains("/"), !filename.contains("\\"),
			filename != ".", filename != "..", !filename.contains("\0"),
			(filename as NSString).pathExtension.lowercased() == "xcb"
		else { throw Err("Use a sibling .xcb filename without directory components.") }
		var url = folder.appendingPathComponent(filename).standardizedFileURL
		var links: Set<URL> = []
		while let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) {
			guard links.insert(url).inserted, links.count < 64 else { throw Err("Circular module symbolic link. Replace it with a sibling source file.") }
			url = URL(fileURLWithPath: destination, relativeTo: url.deletingLastPathComponent()).standardizedFileURL
		}
		url = url.resolvingSymlinksInPath().standardizedFileURL
		guard url.deletingLastPathComponent() == folder else { throw Err("Module sources must stay in the document folder, including symbolic links.") }
		return url
	}

	mutating func reload(_ design: inout Design, documentURL: URL?) {
		loaded.removeAll()
		contents.removeAll()
		design.moduleCache = ModuleCache()
		let ancestors = documentURL.map { [$0.resolvingSymlinksInPath().standardizedFileURL] } ?? []
		for index in design.modules.indices {
			let module = design.modules[index]
			do {
				let content = try resolve(module.filename, stack: design.board.stack, ancestors: ancestors)
				let names = content.ports.keys.sorted()
				if names != module.interface {
					design.moduleCache.notices.append("\(module.reference): module pins changed. Parent wires kept their coordinates; check connections.")
				}
				design.modules[index].interface = names
				design.modules[index].size = content.board.size
				design.modules[index].layerCount = content.board.stack.count
				design.moduleCache.contents[module.id] = content
			} catch {
				design.moduleCache.errors[module.id] = error is Err
					? error.localizedDescription
					: error.localizedDescription + " Restore the source in the document folder and reload."
			}
		}
	}

	private mutating func resolve(_ filename: String, stack: Stack, ancestors: [URL]) throws -> ModuleContent {
		let url = try url(for: filename)
		guard !ancestors.contains(url) else { throw Err("Dependency cycle: \((ancestors + [url]).map(\.lastPathComponent).joined(separator: " → ")). Remove the circular import and reload.") }
		guard ancestors.count < 64 else { throw Err("Module nesting exceeds 64 levels.") }
		var source: Design
		if let cached = loaded[url] { source = cached } else {
			source = try Document.decode(read(url))
			loaded[url] = source
		}
		guard source.board.stack.count <= stack.count else { throw Err("\(filename) needs \(source.board.stack.count) layers; its containing design has \(stack.count). Increase the containing stack and reload.") }
		if let content = contents[url] { return content }
		for i in source.modules.indices {
			let child = source.modules[i]
			let content = try resolve(child.filename, stack: source.board.stack, ancestors: ancestors + [url])
			source.modules[i].interface = content.ports.keys.sorted()
			source.modules[i].size = content.board.size
			source.moduleCache.contents[child.id] = content
		}
		let projection = source.moduleProjection(syncNative: true)
		if let error = projection.interfaceError { throw Err("\(filename): \(error)") }
		let content = ModuleContent(board: projection.design.board, nets: projection.design.nets, ports: projection.ports)
		contents[url] = content
		return content
	}
}
