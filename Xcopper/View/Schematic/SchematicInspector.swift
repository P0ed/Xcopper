import SwiftUI

@MainActor
struct SchematicInspector: View {
	@Binding var design: Design
	var netlist: Netlist
	var selection: Set<Schematic.Ref>
	@FocusState.Binding var focus: Property?
	private var schematic: Schematic { design.schematic }

	var body: some View {
		if let group = selection.group {
			properties(of: group.kind, group.indices)
		} else {
			Text(selection.isEmpty ? "Nothing selected" : "\(selection.count) objects selected")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
	}

	@ViewBuilder
	private func properties(of kind: Schematic.Ref.Kind, _ indices: [Int]) -> some View {
		switch kind {
		case .symbol:
			SymbolsInspector(
				design: $design,
				indices: indices.filter { schematic.symbols.indices.contains($0) },
				focus: $focus
			)
		case .wire:
			WiresInspector(
				wires: indices.filter { schematic.wires.indices.contains($0) }.map { schematic.wires[$0] },
				netlist: netlist
			)
		case .label:
			LabelsInspector(
				labels: $design.schematic.labels,
				indices: indices.filter { schematic.labels.indices.contains($0) },
				focus: $focus
			)
		case .module:
			EmptyView()
		}
	}
}

@MainActor
struct SymbolsInspector: View {
	@Binding var design: Design
	var indices: [Int]
	@FocusState.Binding var focus: Property?

	var body: some View {
		let symbols = design.schematic.symbols
		let kinds = indices.map { symbols[$0].kind }
		let value = $design.value(of: indices.map(Schematic.Ref.symbol))
		ValueRow(title: "Object", value: kinds.map(\.name).shared ?? "Symbols")
		if indices.count > 1 { ValueRow(title: "Count", value: "\(indices.count)") }
		if indices.count == 1, let index = indices.first {
			TextRow(
				title: "Ref",
				prompt: symbols[index].kind.prefix,
				text: $design.reference(of: Schematic.Ref.symbol(index)),
				property: .reference,
				focus: $focus
			)
		}
		TextRow(
			title: "Value",
			prompt: value.wrappedValue == nil ? "Mixed" : "",
			text: value.orEmpty,
			property: .value,
			focus: $focus
		)
		RotationChoice(rotation: $design.schematic.symbols.shared(indices, \.rotation))
		ChoiceRow(title: "Facing", value: $design.schematic.symbols.shared(indices, \.mirrored)) {
			Text("Normal").tag(Bool?.some(false))
			Text("Mirrored").tag(Bool?.some(true))
		}
		if indices.count == 1, let index = indices.first {
			PositionRows(at: $design.schematic.symbols[index, or: symbols[index]].at, focus: $focus)
			ValueRow(title: "Pins", value: "\(symbols[index].pins.count)")
		}
	}
}

@MainActor
struct WiresInspector: View {
	var wires: [Wire]
	var netlist: Netlist

	var body: some View {
		ValueRow(title: "Object", value: wires.count == 1 ? "Wire" : "Wires")
		if wires.count > 1 { ValueRow(title: "Count", value: "\(wires.count)") }
		ValueRow(
			title: "Net",
			value: wires.map { netlist.name(at: $0.start) ?? "unnamed" }.shared ?? "several"
		)
		ValueRow(
			title: "Length",
			value: String.millimeters(wires.reduce(0.0) { $0 + length(from: $1.start, to: $1.end) })
		)
	}
}

@MainActor
struct LabelsInspector: View {
	@Binding var labels: [NetLabel]
	var indices: [Int]
	@FocusState.Binding var focus: Property?

	private var text: Binding<String?> { $labels.shared(indices, \.text) }

	var body: some View {
		ValueRow(title: "Object", value: indices.count == 1 ? "Label" : "Labels")
		if indices.count > 1 { ValueRow(title: "Count", value: "\(indices.count)") }
		TextRow(
			title: "Net",
			prompt: text.wrappedValue == nil ? "Mixed" : "NET",
			text: text.orEmpty,
			property: .text,
			focus: $focus
		)
		if indices.count == 1, let index = indices.first {
			PositionRows(at: $labels[index, or: labels[index]].at, focus: $focus)
		}
	}
}
