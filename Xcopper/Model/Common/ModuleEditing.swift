import SwiftUI

extension Design {
	func moduleReferenceIsValid(_ value: String, ignoring id: UUID? = nil) -> Bool {
		!value.trimmingWhitespace.isEmpty
			&& !modules.contains { $0.id != id && $0.reference == value }
			&& !board.footprints.contains { $0.reference == value }
			&& !schematic.symbols.contains { $0.reference == value }
	}

	mutating func renameReference(_ ref: Ref, to value: String) {
		guard !modules.contains(where: { .module($0.id) != ref && $0.reference == value }) else { return }
		switch ref {
		case let .module(id):
			guard let index = modules.firstIndex(where: { $0.id == id }), moduleReferenceIsValid(value, ignoring: id)
			else { return }
			modules[index].reference = value
		case let .footprint(index) where board.footprints.indices.contains(index):
			board.footprints[index].reference = value
		default: break
		}
	}

	mutating func renameReference(_ ref: Schematic.Ref, to value: String) {
		switch ref {
		case let .module(id): renameReference(Ref.module(id), to: value)
		case let .symbol(index) where schematic.symbols.indices.contains(index):
			guard !modules.contains(where: { $0.reference == value }) else { return }
			schematic.symbols[index].reference = value
		default: break
		}
	}

	mutating func positionModule(_ id: UUID, at point: Pt, layout: Bool) {
		guard let module = modules.first(where: { $0.id == id }) else { return }
		if layout { _ = moveLayout([.module(id)], by: point - module.layoutAt, grid: .mm(0.5)) }
		else { moveSchematic([.module(id)], by: point - module.schematicAt) }
	}

	mutating func turnModule(_ id: UUID, to rotation: Rotation, layout: Bool) {
		guard let module = modules.first(where: { $0.id == id }) else { return }
		let current = layout ? module.layoutRotation : module.schematicRotation
		for _ in 0 ..< ((rotation.rawValue - current.rawValue) & 0b11) {
			if layout { rotateLayout([.module(id)], clockwise: true) }
			else { rotateSchematic([.module(id)], clockwise: true) }
		}
	}

	func layoutRefs(at point: Pt, layer: Int, tolerance: Int, whole: Bool = false) -> Set<Ref> {
		let projection = moduleProjection()
		let hit = projection.design.board.refs(at: point, layer: layer, tolerance: tolerance, whole: whole)
		if !hit.isEmpty { return Set(hit.map { projection.owner($0) }) }
		return modules.last { $0.bounds.outset(tolerance).contains(point) }.map { [.module($0.id)] } ?? []
	}

	func layoutRefs(in rect: Rect, layer: Int, whole: Bool = false) -> Set<Ref> {
		let projection = moduleProjection()
		return Set(projection.design.board.refs(in: rect, layer: layer, whole: whole).map { projection.owner($0) })
			.union(modules.filter { rect.intersects($0.bounds) }.map { .module($0.id) })
	}

	func schematicRef(at point: Pt, tolerance: Int) -> Schematic.Ref? {
		let projection = moduleProjection()
		return projection.design.schematic.hitTest(at: point, tolerance: tolerance).map { projection.owner($0) }
	}

	func schematicRefs(in rect: Rect) -> Set<Schematic.Ref> {
		let projection = moduleProjection()
		return Set(projection.design.schematic.refs(in: rect).map { projection.owner($0) })
	}

	func layoutBounds(_ refs: Set<Ref>) -> Rect? {
		Rect.union([board.bounds(of: refs)].compactMap { $0 } + modules.filter { refs.contains(.module($0.id)) }.map(\.bounds))
	}

	func schematicBounds(_ refs: Set<Schematic.Ref>) -> Rect? {
		Rect.union([schematic.bounds(of: refs)].compactMap { $0 } + modules.filter { refs.contains(.module($0.id)) }.map { $0.symbol.placedExtent })
	}

	mutating func deleteLayout(_ refs: Set<Ref>) {
		removeModules(refs.moduleIDs)
		board.remove(refs)
	}

	mutating func deleteSchematic(_ refs: Set<Schematic.Ref>) {
		removeModules(refs.moduleIDs)
		schematic.remove(refs)
	}

	mutating func duplicateLayout(_ refs: Set<Ref>, by delta: Pt) -> Set<Ref> {
		let ids = duplicateModules(refs.moduleIDs, by: delta)
		return board.duplicate(refs, by: delta, references: usedReferences).union(ids.map(Ref.module))
	}

	mutating func duplicateSchematic(_ refs: Set<Schematic.Ref>, by delta: Pt) -> Set<Schematic.Ref> {
		let ids = duplicateModules(refs.moduleIDs, by: delta)
		return schematic.duplicate(refs, by: delta, references: usedReferences).union(ids.map(Schematic.Ref.module))
	}

	mutating func removeModules(_ ids: Set<UUID>) {
		modules.removeAll { ids.contains($0.id) }
		for id in ids { moduleCache.contents[id] = nil; moduleCache.errors[id] = nil }
	}

	mutating func duplicateModules(_ ids: Set<UUID>, by delta: Pt) -> Set<UUID> {
		var created: Set<UUID> = []
		for original in modules.filter({ ids.contains($0.id) }) {
			var copy = original
			copy.id = UUID()
			copy.reference = nextReference(like: original.reference)
			copy.layoutAt = copy.layoutAt + delta
			copy.schematicAt = copy.schematicAt + delta
			modules.append(copy)
			moduleCache.contents[copy.id] = moduleCache.contents[original.id]
			moduleCache.errors[copy.id] = moduleCache.errors[original.id]
			created.insert(copy.id)
		}
		return created
	}

	@discardableResult
	mutating func moveLayout(_ refs: Set<Ref>, by delta: Pt, grid: Nm) -> Set<Ref>? {
		guard !modules.isEmpty else { return board.move(refs, by: delta, grid: grid) }
		let projection = moduleProjection()
		let selection = Set(refs.map { projection.owner($0) })
		var repair = board
		var moving = selection
		for (index, footprint) in projection.design.board.footprints.enumerated() {
			guard let owner = projection.owners[.footprint(index)] else { continue }
			if selection.contains(.module(owner)) { moving.insert(.footprint(repair.footprints.count)) }
			repair.footprints.append(footprint)
		}
		for (index, via) in projection.design.board.vias.enumerated() {
			guard let owner = projection.owners[.via(index)] else { continue }
			if selection.contains(.module(owner)) { moving.insert(.footprint(repair.footprints.count)) }
			repair.footprints.append(Footprint(
				reference: "", value: "", at: via.at, rotation: .r0, flipped: false,
				pads: [Pad(at: .zero, size: Size(width: Int(via.pad), height: Int(via.pad)), shape: .oval, drill: via.drill, layer: 0, name: "", net: via.net)],
				body: Rect(origin: .zero, size: .zero)
			))
		}
		guard let repaired = repair.move(moving, by: delta, grid: grid) else { return nil }
		repair.footprints = Array(repair.footprints.prefix(board.footprints.count))
		board = repair
		for i in modules.indices where selection.contains(.module(modules[i].id)) { modules[i].layoutAt = modules[i].layoutAt + delta }
		return Set(repaired.filter { ref in
			if case let .footprint(i) = ref { return i < board.footprints.count }
			return true
		})
	}

	mutating func moveSchematic(_ refs: Set<Schematic.Ref>, by delta: Pt) {
		schematic.move(refs, by: delta)
		for i in modules.indices where refs.contains(.module(modules[i].id)) { modules[i].schematicAt = modules[i].schematicAt + delta }
	}

	mutating func rotateLayout(_ refs: Set<Ref>, clockwise: Bool) {
		guard let pivot = layoutBounds(refs)?.center else { return }
		let rotation: Rotation = clockwise ? .r90 : .r270
		board.rotate(refs, clockwise: clockwise, around: pivot)
		for i in modules.indices where refs.contains(.module(modules[i].id)) {
			modules[i].layoutAt = (modules[i].layoutAt - pivot).rotated(rotation) + pivot
			modules[i].layoutRotation = modules[i].layoutRotation.adding(rotation)
		}
	}

	mutating func rotateSchematic(_ refs: Set<Schematic.Ref>, clockwise: Bool) {
		guard let pivot = schematicBounds(refs)?.center else { return }
		let rotation: Rotation = clockwise ? .r90 : .r270
		schematic.rotate(refs, clockwise: clockwise, around: pivot)
		for i in modules.indices where refs.contains(.module(modules[i].id)) {
			modules[i].schematicAt = (modules[i].schematicAt - pivot).rotated(rotation) + pivot
			modules[i].schematicRotation = modules[i].schematicRotation.adding(rotation)
		}
	}

	@discardableResult
	mutating func pasteModules(_ copies: [ModuleInstance], by delta: Pt, documentURL: URL,
		read: @escaping (URL) throws -> Data = { try Data(contentsOf: $0) }) throws -> Set<UUID> {
		var candidate = self
		var ids: Set<UUID> = []
		for var copy in copies {
			copy.id = UUID()
			copy.reference = candidate.nextReference(like: copy.reference)
			copy.layoutAt = copy.layoutAt + delta
			copy.schematicAt = copy.schematicAt + delta
			candidate.modules.append(copy)
			ids.insert(copy.id)
		}
		var resolver = ModuleResolver(folder: documentURL.deletingLastPathComponent(), read: read)
		resolver.reload(&candidate, documentURL: documentURL)
		for id in ids { if let error = candidate.moduleStatus(id) { throw Err(error) } }
		for copy in candidate.modules where ids.contains(copy.id) {
			modules.append(copy)
			moduleCache.contents[copy.id] = candidate.moduleCache.contents[copy.id]
		}
		return ids
	}

	@discardableResult
	mutating func importModule(filename: String, documentURL: URL, read: @escaping (URL) throws -> Data = { try Data(contentsOf: $0) }) throws -> UUID {
		var candidate = self
		let instance = ModuleInstance(reference: nextReference(like: "M"), filename: filename)
		candidate.modules.append(instance)
		var resolver = ModuleResolver(folder: documentURL.deletingLastPathComponent(), read: read)
		resolver.reload(&candidate, documentURL: documentURL)
		if let error = candidate.moduleStatus(instance.id) { throw Err(error) }
		let index = candidate.modules.count - 1
		candidate.modules[index].schematicAt = resolved.schematic.parking(for: candidate.modules[index].symbol)
		candidate.modules[index].layoutAt = parking(
			candidate.modules[index].bounds, in: board.bounds,
			clear: resolved.board.occupied + modules.map(\.bounds)
		)
		modules.append(candidate.modules[index])
		moduleCache.contents[instance.id] = candidate.moduleCache.contents[instance.id]
		return instance.id
	}
}

extension Design {
	func reference(of ref: Ref) -> String {
		switch ref {
		case let .module(id): modules.first { $0.id == id }?.reference ?? ""
		case let .footprint(index): board.footprints.indices.contains(index) ? board.footprints[index].reference : ""
		default: ""
		}
	}

	func reference(of ref: Schematic.Ref) -> String {
		switch ref {
		case let .module(id): modules.first { $0.id == id }?.reference ?? ""
		case let .symbol(index): schematic.symbols.indices.contains(index) ? schematic.symbols[index].reference : ""
		default: ""
		}
	}
}

extension Binding where Value == Design {
	func reference(of ref: Ref) -> Binding<String> {
		Binding<String>(get: { wrappedValue.reference(of: ref) }, set: { wrappedValue.renameReference(ref, to: $0) })
	}

	func reference(of ref: Schematic.Ref) -> Binding<String> {
		Binding<String>(get: { wrappedValue.reference(of: ref) }, set: { wrappedValue.renameReference(ref, to: $0) })
	}
}

extension Set where Element == Ref {
	var moduleIDs: Set<UUID> { Set<UUID>(compactMap { if case let .module(id) = $0 { id } else { nil } }) }
	var hasModules: Bool { contains { if case .module = $0 { true } else { false } } }
}
extension Set where Element == Schematic.Ref {
	var moduleIDs: Set<UUID> { Set<UUID>(compactMap { if case let .module(id) = $0 { id } else { nil } }) }
	var hasModules: Bool { contains { if case .module = $0 { true } else { false } } }
}
