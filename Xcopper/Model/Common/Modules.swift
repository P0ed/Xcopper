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
	var interface: [IODesignator] = []
	var netLabels: [String: String]?
	var size = Size(width: 20 * .mm, height: 20 * .mm)
	var layerCount: Int = 2
	var origin: Point = .zero

	var symbol: Symbol {
		let ports = interface.sorted(by: IODesignator.order)
		var symbol = Symbol.ic(pinNames: ports.map(\.name))
		symbol.reference = reference
		symbol.value = filename
		symbol.at = schematicAt
		symbol.rotation = schematicRotation
		for i in symbol.pins.indices {
			symbol.pins[i].number = String(ports[i].number)
			symbol.pins[i].netLabel = self[netLabel: symbol.pins[i].number]
		}
		return symbol
	}

	subscript(netLabel number: String) -> String? {
		get { netLabels?[number] }
		set {
			var labels = netLabels ?? [:]
			labels[number] = newValue.flatMap { $0.trimmingWhitespace.isEmpty ? nil : $0 }
			netLabels = labels.isEmpty ? nil : labels
		}
	}

	func place(_ point: Point) -> Point { (point - origin).rotated(layoutRotation) + layoutAt }
	var bounds: Rect { Rect(from: place(.zero), to: place(Point(x: size.width, y: size.height))) }
}

extension ModuleInstance {
	enum CodingKeys: String, CodingKey {
		case id, reference, filename, schematicAt, schematicRotation, layoutAt, layoutRotation, interface, netLabels, size, layerCount, origin
	}

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		id = try values.decode(UUID.self, forKey: .id)
		reference = try values.decode(String.self, forKey: .reference)
		filename = try values.decode(String.self, forKey: .filename)
		schematicAt = try values.decode(Point.self, forKey: .schematicAt)
		schematicRotation = try values.decode(Rotation.self, forKey: .schematicRotation)
		layoutAt = try values.decode(Point.self, forKey: .layoutAt)
		layoutRotation = try values.decode(Rotation.self, forKey: .layoutRotation)
		interface = try values.decode([IODesignator].self, forKey: .interface)
		netLabels = try values.decodeIfPresent([String: String].self, forKey: .netLabels)
		size = try values.decode(Size.self, forKey: .size)
		layerCount = try values.decode(Int.self, forKey: .layerCount)
		origin = try values.decodeIfPresent(Point.self, forKey: .origin) ?? .zero
	}
}

struct ModuleContent: Equatable {
	var board: Board
	var nets: [Net]
	var ports: [String: Net.ID]
	var interface: [IODesignator]
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
	var localNets: Set<Net.ID> = []
	var interface: [IODesignator] = []
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
		var moduleNets: Set<Int> = []
		var parentNets = Set(board.traces.compactMap(\.net))
		parentNets.formUnion(board.vias.compactMap(\.net))
		for footprint in board.footprints { parentNets.formUnion(footprint.pads.compactMap(\.net)) }
		var merge = UnionFind<Int>()
		let netIDsByName = Dictionary(self.nets.map { ($0.name, $0.id) }, uniquingKeysWith: { a, _ in a })
		func global(_ name: String) -> Int? {
			guard supplyNames.contains(name) else { return nil }
			let id = netIDsByName[name] ?? moduleNetID("power/\(name)")
			nets[id] = name
			parentNets.insert(id)
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
				let shared = global(net.name)
				let id = shared ?? moduleNetID("\(module.id)/\(net.id)")
				mapping[net.id] = id
				if shared == nil { moduleNets.insert(id) }
				if nets[id] == nil { nets[id] = "\(module.reference).\(net.name)" }
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
				footprint.reference = "\(module.reference).\(footprint.reference)"
				result.owners[.footprint(result.design.board.footprints.count)] = module.id
				result.design.board.footprints.append(footprint)
			}
		}

		let electrical = result.design.schematic
		let netlist = Netlist(electrical)
		var footprintsByReference: [String: [Int]] = [:]
		for i in board.footprints.indices { footprintsByReference[board.footprints[i].reference, default: []].append(i) }
		var pointNets: [Point: Int] = [:]
		var assignments: [(Int, Int, Int)] = []
		var wired: Set<String> = []
		for group in netlist.groups {
			let nodes = group.nodes.sorted { ($0.symbol, $0.pin) < ($1.symbol, $1.pin) }
			let active = nodes.count > 1 || group.name != nil
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
			let key = group.pinNames(in: electrical).joined(separator: "/")
			let fallback = moduleNetID("group/\(key.isEmpty ? String(describing: group.points.sorted(by: Point.order)) : key)")
			let named = group.name.map { name in netIDsByName[name] ?? moduleNetID("named/\(name)") }
			let power = connected.first { id in nets[id].map(supplyNames.contains) ?? false }
			let id = named ?? power ?? connected.first ?? fallback
			if nets[id] == nil { nets[id] = group.name ?? "N$\(key.isEmpty ? String(-fallback) : key)" }
			for other in connected { merge.union(other, id) }
			if active { parentNets.insert(id) }
			for point in group.points { pointNets[point] = id }
			if syncNative, active {
				result.report.assigned += pads.count
				for (i, j) in pads { assignments.append((i, j, id)) }
			}
		}
		for (i, j, id) in assignments { result.design.board.footprints[i].pads[j].net = id }
		result.design.board.mapNets { $0.map { merge.find($0) } }
		var interface: [Int: IODesignator] = [:]
		for symbol in electrical.symbols {
			for pin in symbol.placedPins {
				if pin.hasInvalidIO {
					result.interfaceError = "\(symbol.reference).\(pin.number): use # followed by a positive pin number and a net name, such as #1 OUT1."
					continue
				}
				guard let port = pin.ioDesignator, let id = pointNets[pin.at].map({ merge.find($0) }) else { continue }
				let number = String(port.number)
				if let existing = interface[port.number], existing != port {
					result.interfaceError = "Ambiguous #\(port.number): each IO pin number must have one name."
				}
				if let existing = result.ports[number], existing != id {
					result.interfaceError = "Ambiguous #\(port.number) \(port.name): repeated designators must resolve to the same net."
				}
				interface[port.number] = port
				result.ports[number] = id
			}
		}
		result.interface = interface.values.sorted(by: IODesignator.order)
		result.report.missingFootprints = Set(result.report.missingFootprints).sorted()
		result.report.missingPins.sort()
		result.report.extraFootprints = board.footprints.map(\.reference).filter { !wired.contains($0) }.sorted()
		let nativeIDs = Set(self.nets.map(\.id))
		result.design.nets = nets.keys.sorted().filter { nativeIDs.contains($0) || merge.find($0) == $0 }.map { Net(id: $0, name: nets[$0]!) }
		let promoted = Set(parentNets.map { merge.find($0) })
		result.localNets = Set(moduleNets.map { merge.find($0) }).subtracting(promoted)
		result.report.created = result.design.nets.filter { !nativeIDs.contains($0.id) && !result.localNets.contains($0.id) }.map(\.name)
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
				if content.interface != module.interface {
					design.moduleCache.notices.append("\(module.reference): module pins changed. Parent wires kept their coordinates; check connections.")
				}
				design.modules[index].interface = content.interface
				design.modules[index].size = content.board.size
				design.modules[index].layerCount = content.board.stack.count
				design.modules[index].origin = content.board.origin
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
			source.modules[i].interface = content.interface
			source.modules[i].size = content.board.size
			source.modules[i].origin = content.board.origin
			source.moduleCache.contents[child.id] = content
		}
		let projection = source.moduleProjection(syncNative: true)
		if let error = projection.interfaceError { throw Err("\(filename): \(error)") }
		let content = ModuleContent(board: projection.design.board, nets: projection.design.nets, ports: projection.ports, interface: projection.interface)
		contents[url] = content
		return content
	}
}
