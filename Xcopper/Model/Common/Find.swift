extension Design {

	func layoutRefs(matching query: String) -> Set<Ref> {
		footprints(for: schematicRefs(matching: query))
	}

	func schematicRefs(matching query: String) -> Set<SchematicRef> {
		let query = query.lowercased()
		guard !query.isEmpty else { return [] }
		return Set(
			board.footprints.indices
				.filter { index in
					matches(query, board.footprints[index].reference, board.footprints[index].value)
						|| board.footprints[index].symbol.pins.contains { matches(query, $0.netName ?? "", $0.netLabel ?? "") }
				}
				.map(SchematicRef.symbol)
		)
		.union(modules.filter {
			matches(query, $0.reference, $0.name)
				|| $0.symbol.pins.contains { matches(query, $0.netName ?? "", $0.netLabel ?? "") }
		}.map { SchematicRef.module($0.id) })
	}

	private func matches(_ query: String, _ fields: String...) -> Bool {
		fields.contains { field in field.lowercased().hasPrefix(query) }
	}
}
