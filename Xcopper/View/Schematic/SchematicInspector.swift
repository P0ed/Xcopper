import SwiftUI

@MainActor
struct SchematicInspector: View {
	@Binding var schematic: Schematic
	var netlist: Netlist
	var selection: Set<Schematic.Ref>
	@FocusState.Binding var focus: Property?

	var body: some View {
		if selection.count == 1, let ref = selection.first {
			properties(of: ref)
		} else {
			Text(selection.isEmpty ? "Nothing selected" : "\(selection.count) objects selected")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
	}

	@ViewBuilder
	private func properties(of ref: Schematic.Ref) -> some View {
		switch ref {
		case let .symbol(index) where schematic.symbols.indices.contains(index):
			SymbolInspector(
				symbol: $schematic.symbols[index, or: schematic.symbols[index]],
				focus: $focus
			)
		case let .wire(index) where schematic.wires.indices.contains(index):
			WireInspector(wire: schematic.wires[index], netlist: netlist)
		case let .label(index) where schematic.labels.indices.contains(index):
			LabelInspector(
				label: $schematic.labels[index, or: schematic.labels[index]],
				focus: $focus
			)
		default:
			EmptyView()
		}
	}
}

@MainActor
struct SymbolInspector: View {
	@Binding var symbol: Symbol
	@FocusState.Binding var focus: Property?

	var body: some View {
		ValueRow(title: "Object", value: symbol.kind.name)
		TextRow(
			title: "Ref",
			prompt: symbol.kind.prefix,
			text: $symbol.reference,
			property: .reference,
			focus: $focus
		)
		TextRow(
			title: symbol.kind.isPower ? "Net" : "Value",
			prompt: symbol.kind.defaultValue,
			text: $symbol.value,
			property: .value,
			focus: $focus
		)
		RotationChoice(rotation: $symbol.rotation)
		ChoiceRow(title: "Facing", value: $symbol.mirrored) {
			Text("Normal").tag(false)
			Text("Mirrored").tag(true)
		}
		PositionRows(at: $symbol.at, focus: $focus)
		ValueRow(title: "Pins", value: "\(symbol.pins.count)")
	}
}

@MainActor
struct WireInspector: View {
	var wire: Wire
	var netlist: Netlist

	var body: some View {
		ValueRow(title: "Object", value: "Wire")
		ValueRow(title: "Net", value: netlist.name(at: wire.start) ?? "unnamed")
		ValueRow(title: "Length", value: millimeters(length(from: wire.start, to: wire.end)))
	}
}

@MainActor
struct LabelInspector: View {
	@Binding var label: NetLabel
	@FocusState.Binding var focus: Property?

	var body: some View {
		ValueRow(title: "Object", value: "Label")
		TextRow(
			title: "Net",
			prompt: "NET",
			text: $label.text,
			property: .text,
			focus: $focus
		)
		PositionRows(at: $label.at, focus: $focus)
	}
}
