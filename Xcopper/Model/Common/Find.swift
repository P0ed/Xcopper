extension Design {

	func layoutRefs(matching query: String) -> Set<Ref> {
		footprints(for: schematicRefs(matching: query))
	}

	func schematicRefs(matching query: String) -> Set<Schematic.Ref> {
		let query = query.lowercased()
		guard !query.isEmpty else { return [] }
		return Set(
			schematic.symbols.indices
				.filter { index in
					matches(query, schematic.symbols[index].reference, schematic.symbols[index].value)
						|| schematic.symbols[index].pins.contains { matches(query, $0.netName ?? "", $0.netLabel ?? "") }
				}
				.map(Schematic.Ref.symbol)
		)
		.union(modules.filter {
			matches(query, $0.reference, $0.name)
				|| $0.symbol.pins.contains { matches(query, $0.netName ?? "", $0.netLabel ?? "") }
		}.map { Schematic.Ref.module($0.id) })
	}

	private func matches(_ query: String, _ fields: String...) -> Bool {
		fields.contains { field in field.lowercased().hasPrefix(query) }
	}
}
