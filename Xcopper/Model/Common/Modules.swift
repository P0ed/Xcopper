import Foundation
import Synchronization

final class ModuleProjectionCache: Sendable, Equatable {
	static func == (_: ModuleProjectionCache, _: ModuleProjectionCache) -> Bool { true }

	private struct Key: Hashable {
		var syncNative: Bool
		var resolvingParameters: Bool
	}

	private let projections = Mutex<[Key: ModuleProjection]>([:])

	func value(syncNative: Bool, resolvingParameters: Bool, build: () -> ModuleProjection) -> ModuleProjection {
		projections.withLock { values in
			let key = Key(syncNative: syncNative, resolvingParameters: resolvingParameters)
			if let cached = values[key] { return cached }
			let projection = build()
			values[key] = projection
			return projection
		}
	}
}

struct ModuleParameter: Equatable, Codable, Identifiable {
	var name: String
	var defaultValue: String
	var id: String { name }

	static func name(in value: String) -> String? {
		guard value.hasPrefix("#") else { return nil }
		let name = value.dropFirst().prefix { !$0.isWhitespace }
		return name.isEmpty ? nil : String(name)
	}
}

struct ModuleInstance: Equatable, Codable, Identifiable {
	var id = UUID()
	var reference: String
	var filename: String
	var name: String { ModuleLibrary.name(of: filename) }
	var schematicAt: Point = .zero
	var schematicRotation: Rotation = .r0
	var layoutAt: Point = .zero
	var layoutRotation: Rotation = .r0
	var interface: [IODesignator] = []
	var netLabels: [String: String]?
	var parameters: [ModuleParameter] = []
	var parameterValues: [String: String] = [:]
	var size = Size(width: 20 * .mm, height: 20 * .mm)
	var layerCount: Int = 2

	var symbol: Symbol {
		let ports = interface.sorted(by: IODesignator.order)
		var symbol = Symbol.ic(pinNames: ports.map(\.name))
		symbol.reference = reference
		symbol.value = name
		symbol.at = schematicAt
		symbol.rotation = schematicRotation
		for i in symbol.pins.indices {
			symbol.pins[i].number = String(ports[i].number)
			symbol.pins[i].netLabel = self[netLabel: symbol.pins[i].number]
		}
		if !parameters.isEmpty {
			symbol.body.size.height += parameterHeight
			symbol.glyph = [.rect(symbol.body)]
		}
		return symbol
	}

	func value(for parameter: ModuleParameter) -> String {
		parameterValues[parameter.name] ?? parameter.defaultValue
	}

	var parameterLines: [String] {
		parameters.flatMap { "\($0.name): \(value(for: $0))".components(separatedBy: .newlines) }
	}

	var parameterHeight: µm { parameterLines.count * 2_540 }

	func parameterBounds(in symbol: Symbol) -> Rect {
		Rect(
			origin: Point(x: symbol.body.minX, y: symbol.body.maxY - parameterHeight),
			size: Size(width: symbol.body.size.width, height: parameterHeight)
		)
	}

	subscript(netLabel number: String) -> String? {
		get { netLabels?[number] }
		set {
			var labels = netLabels ?? [:]
			labels[number] = newValue.flatMap { $0.trimmingWhitespace.isEmpty ? nil : $0 }
			netLabels = labels.isEmpty ? nil : labels
		}
	}

	func place(_ point: Point) -> Point {
		(point - Point(x: size.width / 2, y: size.height / 2)).rotated(layoutRotation) + layoutAt
	}
	var bounds: Rect { Rect(from: place(.zero), to: place(Point(x: size.width, y: size.height))) }
}

extension ModuleInstance {
	enum CodingKeys: String, CodingKey {
		case id, reference, filename, schematicAt, schematicRotation, layoutAt, layoutRotation, interface, netLabels, parameters, parameterValues, size, layerCount
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
		parameters = try values.decodeIfPresent([ModuleParameter].self, forKey: .parameters) ?? []
		parameterValues = try values.decodeIfPresent([String: String].self, forKey: .parameterValues) ?? [:]
		size = try values.decode(Size.self, forKey: .size)
		layerCount = try values.decode(Int.self, forKey: .layerCount)
	}
}

struct ModuleContent: Equatable {
	var board: Board
	var nets: [Net]
	var ports: [String: Net.ID]
	var interface: [IODesignator]
	var parameters: [ModuleParameter] = []
}

struct ModulePlacement: Equatable {
	var instance: ModuleInstance
	var content: ModuleContent
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

let supplyNames: Set<String> = ["GND", "VCC", "VEE"]

private func moduleNetID(_ key: String) -> Int {
	let hash = key.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
	return -Int(hash & 0x3fff_ffff_ffff_ffff) - 1
}

extension Design {
	mutating func synchronizeParameters() {
		let values = schematic.symbols.map(\.value) + modules.flatMap { module in
			module.parameters.compactMap { module.parameterValues[$0.name] }
		}
		let names = Set(values.compactMap(ModuleParameter.name(in:)))
		let defaults = Dictionary(parameters.map { ($0.name, $0.defaultValue) }, uniquingKeysWith: { first, _ in first })
		let next = names.sorted {
			let order = $0.compare($1, options: .numeric)
			return order == .orderedSame ? $0 < $1 : order == .orderedAscending
		}
			.map { ModuleParameter(name: $0, defaultValue: defaults[$0] ?? "") }
		if parameters != next { parameters = next }
	}

	private var parameterReferences: [String: String] {
		Dictionary(schematic.symbols.compactMap { symbol in
			ModuleParameter.name(in: symbol.value).map { (symbol.reference, $0) }
		}, uniquingKeysWith: { first, _ in first })
	}

	func applyParameterDefaults(to board: inout Board) {
		guard !parameters.isEmpty else { return }
		let references = parameterReferences
		let defaults = Dictionary(parameters.map { ($0.name, $0.defaultValue) }, uniquingKeysWith: { first, _ in first })
		board.footprints.modifyEach { footprint in
			if let name = references[footprint.reference] ?? ModuleParameter.name(in: footprint.value),
				let value = defaults[name] {
				footprint.value = value
			}
		}
	}

	var moduleErrors: [String] {
		modules.compactMap { module in
			moduleStatus(module.id).map { "\(module.reference) (\(module.name)): \($0)" }
		}
	}

	func moduleStatus(_ id: UUID) -> String? {
		if let error = moduleCache.errors[id] { return error }
		guard let content = moduleCache.contents[id] else { return "Unresolved. Select a source or use Reload Modules." }
		return content.board.stack.count > board.stack.count ? "Source needs more copper layers. Increase the board stack and reload." : nil
	}

	func canRestack(_ stack: Stack) -> Bool {
		modules.allSatisfy { max($0.layerCount, moduleCache.contents[$0.id]?.board.stack.count ?? 0) <= stack.count }
	}

	var resolved: Design { moduleProjection().design }

	func buildModuleProjection(syncNative: Bool, resolvingParameters: Bool) -> ModuleProjection {
		var result = ModuleProjection(design: self)
		result.design.modules = []
		result.design.moduleCache = ModuleCache()
		let parameterReferences = self.parameterReferences
		for index in result.design.board.footprints.indices {
			if let name = parameterReferences[result.design.board.footprints[index].reference] {
				result.design.board.footprints[index].value = "#" + name
			}
		}
		var nets = Dictionary(nets.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
		var portsBySymbol: [Int: [String: Int]] = [:]
		var merge = UnionFind<Int>()
		var netIDsByName = Dictionary(self.nets.map { ($0.name, $0.id) }, uniquingKeysWith: { a, _ in a })
		func global(_ name: String) -> Int? {
			guard supplyNames.contains(name) else { return nil }
			let id = netIDsByName[name] ?? moduleNetID("power/\(name)")
			nets[id] = name
			netIDsByName[name] = id
			return id
		}
		for module in modules {
			let symbolIndex = result.design.schematic.symbols.count
			result.symbolOwners[.symbol(symbolIndex)] = module.id
			let status = moduleStatus(module.id)
			var symbol = module.symbol
			if status != nil { symbol.value = "⚠ Unresolved: " + module.name }
			result.design.schematic.symbols.append(symbol)
			guard status == nil, let content = moduleCache.contents[module.id] else { continue }
			var mapping: [Int: Int] = [:]
			for net in content.nets {
				let shared = global(net.name)
				let id = shared ?? moduleNetID("\(module.id)/\(net.id)")
				mapping[net.id] = id
				if shared == nil {
					let name = "\(module.reference).\(net.name)"
					result.localNets.insert(id)
					if let existing = netIDsByName[name], existing != id {
						merge.union(existing, id)
						nets.removeValue(forKey: existing)
					}
					nets[id] = name
					netIDsByName[name] = id
				}
			}
			portsBySymbol[symbolIndex] = content.ports.mapValues { mapping[$0]! }
			var imported = content.board
			let parameterValues = Dictionary(content.parameters.map { ($0.name, module.value(for: $0)) }, uniquingKeysWith: { first, _ in first })
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
				if let name = ModuleParameter.name(in: footprint.value), let value = parameterValues[name] {
					footprint.value = value
				}
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
		var groupsByNet: [Net.ID: Set<Int>] = [:]
		for (index, group) in netlist.groups.enumerated() {
			if let name = group.name, let id = netIDsByName[name] { groupsByNet[id, default: []].insert(index) }
			for node in group.nodes where node.symbol < schematic.symbols.count {
				let symbol = electrical.symbols[node.symbol]
				let pin = symbol.pins[node.pin].number
				for i in footprintsByReference[symbol.reference] ?? [] {
					for pad in board.footprints[i].pads where pad.name == pin {
						if let id = pad.net { groupsByNet[id, default: []].insert(index) }
					}
				}
			}
		}
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
						if let id = board.footprints[i].pads[j].net, groupsByNet[id]?.count == 1 {
							connected.append(id)
						}
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
			for point in group.points { pointNets[point] = id }
			if active {
				if syncNative { result.report.assigned += pads.count }
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
		result.report.created = result.design.nets.filter { !nativeIDs.contains($0.id) && !result.localNets.contains($0.id) }.map(\.name)
		if resolvingParameters {
			applyParameterDefaults(to: &result.design.board)
		}
		return result
	}
}

struct ModuleLibrary {
	private var sources: [String: URL] = [:]
	var urls: [URL] { Array(sources.values) }

	static func name(of filename: String) -> String {
		let name = (filename as NSString).lastPathComponent
		return (name as NSString).pathExtension.lowercased() == "xcb" ? (name as NSString).deletingPathExtension : name
	}

	private static func key(_ name: String) -> String {
		name.precomposedStringWithCanonicalMapping.lowercased()
	}

	init(sources: [URL]) throws {
		for source in sources {
			let url = source.resolvingSymlinksInPath().standardizedFileURL
			let name = Self.name(of: url.lastPathComponent)
			let key = Self.key(name)
			guard let existing = self.sources[key] else {
				self.sources[key] = url
				continue
			}
			guard existing == url else {
				throw Err("Multiple module files are named “\(name)”. Give each module a unique name and reload.")
			}
		}
	}

	init(folder: URL, access: (URL) throws -> Void = { _ in }) throws {
		let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isPackageKey, .isAliasFileKey]
		var pending = [folder]
		var visited: Set<String> = []
		var sources: [URL] = []
		while let next = pending.popLast() {
			try access(next)
			let folder = next.resolvingSymlinksInPath().standardizedFileURL
			guard visited.insert(folder.path).inserted else { continue }
			let entries: [URL]
			do {
				entries = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
			} catch { throw Err("Could not search folder “\(folder.lastPathComponent)”. Check folder access and reload modules.") }
			for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
				var url = entry
				var links: Set<URL> = []
				while true {
					guard links.insert(url.standardizedFileURL).inserted, links.count <= 64 else {
						throw Err("Circular module alias “\(Self.name(of: entry.lastPathComponent))”. Remove the alias and reload.")
					}
					try access(url.deletingLastPathComponent())
					if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) {
						url = URL(fileURLWithPath: target, relativeTo: url.deletingLastPathComponent()).standardizedFileURL
						continue
					}
					let values: URLResourceValues
					do { values = try url.resourceValues(forKeys: keys) }
					catch { throw Err("Could not inspect “\(Self.name(of: entry.lastPathComponent))”. Check its access or alias target and reload modules.") }
					if values.isAliasFile == true {
						do { url = try URL(resolvingAliasFileAt: url, options: [.withoutUI, .withoutMounting]) }
						catch { throw Err("Could not resolve alias “\(Self.name(of: entry.lastPathComponent))”. Repair the alias and reload modules.") }
						continue
					}
					if values.isDirectory == true {
						if values.isPackage != true { pending.append(url) }
					} else if values.isRegularFile == true, url.pathExtension.lowercased() == "xcb" {
						sources.append(url)
					}
					break
				}
			}
		}
		try self.init(sources: sources)
	}

	func url(for filename: String) throws -> URL {
		let name = Self.name(of: filename)
		guard let url = sources[Self.key(name)] else {
			throw Err("Module “\(name)” was not found. Add it to this folder or a subfolder, or add a folder alias, then reload.")
		}
		return url
	}
}

struct ModuleResolver {
	var folder: URL
	var read: (URL) throws -> Data = { try Data(contentsOf: $0) }
	var library: ModuleLibrary?
	private var catalog: Result<ModuleLibrary, Error>?
	private var loaded: [URL: Design] = [:]
	private var contents: [URL: ModuleContent] = [:]

	init(folder: URL, library: ModuleLibrary? = nil, read: @escaping (URL) throws -> Data = { try Data(contentsOf: $0) }) {
		self.folder = folder.resolvingSymlinksInPath().standardizedFileURL
		self.library = library
		self.read = read
	}

	mutating func url(for filename: String) throws -> URL {
		let result = catalog ?? Result { try library ?? ModuleLibrary(folder: folder) }
		catalog = result
		return try result.get().url(for: filename)
	}

	mutating func reload(_ design: inout Design, documentURL: URL?) {
		loaded.removeAll()
		contents.removeAll()
		catalog = nil
		design.moduleCache = ModuleCache()
		let ancestors = documentURL.map { [$0.resolvingSymlinksInPath().standardizedFileURL] } ?? []
		for index in design.modules.indices {
			let module = design.modules[index]
			do {
				let content = try resolve(module.name, stack: design.board.stack, ancestors: ancestors)
				if content.interface != module.interface {
					design.moduleCache.notices.append("\(module.reference): module pins changed. Parent wires kept their coordinates; check connections.")
				}
				design.modules[index].interface = content.interface
				design.modules[index].parameters = content.parameters
				design.modules[index].size = content.board.size
				design.modules[index].layerCount = content.board.stack.count
				design.moduleCache.contents[module.id] = content
			} catch {
				design.moduleCache.errors[module.id] = error is Err
					? error.localizedDescription
					: "Could not load module “\(module.name)”. Check the source and folder access, then reload."
			}
		}
	}

	private mutating func resolve(_ name: String, stack: Stack, ancestors: [URL]) throws -> ModuleContent {
		let url = try url(for: name)
		guard !ancestors.contains(url) else { throw Err("Dependency cycle: \((ancestors + [url]).map { ModuleLibrary.name(of: $0.lastPathComponent) }.joined(separator: " → ")). Remove the circular import and reload.") }
		guard ancestors.count < 64 else { throw Err("Module nesting exceeds 64 levels.") }
		var source: Design
		if let cached = loaded[url] { source = cached } else {
			do { source = try Document.decode(read(url)) }
			catch let error as Err { throw error }
			catch { throw Err("Could not read module “\(name)”. Check that its source is accessible and contains a valid design, then reload.") }
			loaded[url] = source
		}
		guard source.board.stack.count <= stack.count else { throw Err("\(name) needs \(source.board.stack.count) layers; its containing design has \(stack.count). Increase the containing stack and reload.") }
		if let content = contents[url] { return content }
		for i in source.modules.indices {
			let child = source.modules[i]
			let content = try resolve(child.name, stack: source.board.stack, ancestors: ancestors + [url])
			source.modules[i].interface = content.interface
			source.modules[i].parameters = content.parameters
			source.modules[i].size = content.board.size
			source.moduleCache.contents[child.id] = content
		}
		let projection = source.moduleProjection(syncNative: true, resolvingParameters: false)
		if let error = projection.interfaceError { throw Err("\(name): \(error)") }
		let content = ModuleContent(
			board: projection.design.board, nets: projection.design.nets, ports: projection.ports,
			interface: projection.interface, parameters: source.parameters
		)
		contents[url] = content
		return content
	}
}
