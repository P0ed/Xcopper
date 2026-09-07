import SwiftUI

@MainActor
struct SchematicInspector: View {
	@Binding var design: Design
	var netlist: Netlist
	var selection: Set<Schematic.Ref>
	@FocusState.Binding var focus: Property?
	private var schematic: Schematic { design.schematic }

	var body: some View {
		if selection.count == 1, let ref = selection.first {
			properties(of: ref)
		} else if selection.count > 1, let group = selection.group {
			properties(of: group.kind, group.indices)
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
				symbol: $design.schematic.symbols[index, or: schematic.symbols[index]],
				reference: $design.reference(of: Schematic.Ref.symbol(index)),
				value: $design.value(of: Schematic.Ref.symbol(index)).orEmpty,
				focus: $focus
			)
		case let .wire(index) where schematic.wires.indices.contains(index):
			WireInspector(wire: schematic.wires[index], netlist: netlist)
		case let .flag(index) where schematic.flags.indices.contains(index):
			FlagInspector(
				flag: $design.schematic.flags[index, or: schematic.flags[index]],
				focus: $focus
			)
		case let .label(index) where schematic.labels.indices.contains(index):
			LabelInspector(
				label: $design.schematic.labels[index, or: schematic.labels[index]],
				focus: $focus
			)
		default:
			EmptyView()
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
		case .flag:
			FlagsInspector(
				flags: $design.schematic.flags,
				indices: indices.filter { schematic.flags.indices.contains($0) },
				focus: $focus
			)
		case .module:
			EmptyView()
		}
	}
}

@MainActor
struct SymbolInspector: View {
	@Binding var symbol: Symbol
	@Binding var reference: String
	@Binding var value: String
	@FocusState.Binding var focus: Property?

	var body: some View {
		ValueRow(title: "Object", value: symbol.kind.name)
		TextRow(
			title: "Ref",
			prompt: symbol.kind.prefix,
			text: $reference,
			property: .reference,
			focus: $focus
		)
		TextRow(
			title: "Value",
			prompt: "",
			text: $value,
			property: .value,
			focus: $focus
		)
		RotationChoice(rotation: $symbol.rotation.optional)
		ChoiceRow(title: "Facing", value: $symbol.mirrored.optional) {
			Text("Normal").tag(Bool?.some(false))
			Text("Mirrored").tag(Bool?.some(true))
		}
		PositionRows(at: $symbol.at, focus: $focus)
		ValueRow(title: "Pins", value: "\(symbol.pins.count)")
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
		ValueRow(title: "Count", value: "\(indices.count)")
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
struct WiresInspector: View {
	var wires: [Wire]
	var netlist: Netlist

	var body: some View {
		ValueRow(title: "Object", value: "Wires")
		ValueRow(title: "Count", value: "\(wires.count)")
		ValueRow(
			title: "Net",
			value: wires.map { netlist.name(at: $0.start) ?? "unnamed" }.shared ?? "several"
		)
		ValueRow(
			title: "Length",
			value: millimeters(wires.reduce(0.0) { $0 + length(from: $1.start, to: $1.end) })
		)
	}
}

@MainActor
struct FlagInspector: View {
	@Binding var flag: Flag
	@FocusState.Binding var focus: Property?

	var body: some View {
		ValueRow(title: "Object", value: "\(flag.kind.name) flag")
		TextRow(
			title: "Net",
			prompt: flag.kind.defaultNet,
			text: $flag.net,
			property: .text,
			focus: $focus
		)
		RotationChoice(rotation: $flag.rotation.optional)
		PositionRows(at: $flag.at, focus: $focus)
	}
}

@MainActor
struct FlagsInspector: View {
	@Binding var flags: [Flag]
	var indices: [Int]
	@FocusState.Binding var focus: Property?

	private var net: Binding<String?> { $flags.shared(indices, \.net) }

	var body: some View {
		ValueRow(title: "Object", value: "Flags")
		ValueRow(title: "Count", value: "\(indices.count)")
		TextRow(
			title: "Net",
			prompt: net.wrappedValue == nil ? "Mixed" : "NET",
			text: net.orEmpty,
			property: .text,
			focus: $focus
		)
		RotationChoice(rotation: $flags.shared(indices, \.rotation))
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

@MainActor
struct LabelsInspector: View {
	@Binding var labels: [NetLabel]
	var indices: [Int]
	@FocusState.Binding var focus: Property?

	private var text: Binding<String?> { $labels.shared(indices, \.text) }

	var body: some View {
		ValueRow(title: "Object", value: "Labels")
		ValueRow(title: "Count", value: "\(indices.count)")
		TextRow(
			title: "Net",
			prompt: text.wrappedValue == nil ? "Mixed" : "NET",
			text: text.orEmpty,
			property: .text,
			focus: $focus
		)
	}
}
