import SwiftUI

@MainActor
struct LayoutInspector: View {
	@Binding var design: Design
	var selection: Set<Ref>
	@FocusState.Binding var focus: Property?
	var selectFootprint: (Int) -> Void

	private var board: Board { design.board }

	var body: some View {
		if selection.count == 1, let ref = selection.first, ref.kind == .module || ref.kind == .pad {
			properties(of: ref)
		} else if !selection.isEmpty, selection.allSatisfy({ $0.kind == .pad }) {
			PadsInspector(design: design, refs: selection)
		} else if let group = selection.group {
			properties(of: group.kind, group.indices)
		} else {
			Text(selection.isEmpty ? "Nothing selected" : "\(selection.count) objects selected")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
	}

	@ViewBuilder
	private func properties(of ref: Ref) -> some View {
		switch ref {
		case let .module(id):
			ModuleInspector(design: $design, id: id, layout: true, focus: $focus)
		case let .pad(index, _) where board.placedPad(ref) != nil:
			PadsInspector(design: design, refs: [ref])
			Button("Select footprint") { selectFootprint(index) }
				.buttonStyle(.borderless)
		default:
			EmptyView()
		}
	}

	@ViewBuilder
	private func properties(of kind: Ref.Kind, _ indices: [Int]) -> some View {
		switch kind {
		case .trace:
			TracesInspector(
				traces: $design.board.traces,
				indices: indices.filter { board.traces.indices.contains($0) },
				nets: design.nets,
				stack: board.stack,
				focus: $focus
			)
		case .via:
			ViasInspector(
				vias: $design.board.vias,
				indices: indices.filter { board.vias.indices.contains($0) },
				nets: design.nets,
				stack: board.stack,
				focus: $focus
			)
		case .hole:
			HolesInspector(
				holes: $design.board.holes,
				indices: indices.filter { board.holes.indices.contains($0) },
				focus: $focus
			)
		case .footprint:
			footprints(indices.filter { board.footprints.indices.contains($0) })
		case .module, .pad:
			EmptyView()
		}
	}

	@ViewBuilder
	private func footprints(_ indices: [Int]) -> some View {
		if indices.count == 1, let index = indices.first {
			FootprintInspector(
				footprint: $design.board.footprints[index, or: board.footprints[index]],
				reference: $design.reference(of: Ref.footprint(index)),
				value: $design.value(of: Ref.footprint(index)).orEmpty,
				stack: board.stack,
				focus: $focus
			)
		} else {
			FootprintsInspector(design: $design, indices: indices, stack: board.stack, focus: $focus)
		}
	}
}

@MainActor
struct PadsInspector: View {
	var design: Design
	var refs: Set<Ref>

	private var validRefs: [Ref] {
		refs.filter { design.board.placedPad($0) != nil }
	}

	private var netName: String {
		guard let net = validRefs.map({ design.board[net: $0] }).shared else { return "Mixed" }
		return design.net(net)?.name ?? "None"
	}

	var body: some View {
		ValueRow(title: "Object", value: refs.count == 1 ? "Pad" : "Pads")
		if validRefs.count == 1, let (footprint, pad) = design.board.placedPad(validRefs[0]) {
			ValueRow(title: "Ref", value: footprint.reference)
			ValueRow(title: "Pad", value: pad.name)
			ValueRow(title: "Shape", value: pad.shape == .rect ? "Rectangle" : "Oval")
			ValueRow(title: "Width", value: millimeters(pad.size.width.mm))
			ValueRow(title: "Height", value: millimeters(pad.size.height.mm))
			if pad.isThrough { ValueRow(title: "Drill", value: millimeters(pad.drill.mm)) }
			ValueRow(title: "Layer", value: pad.isThrough ? "Through hole" : design.board.stack.name(of: footprint.layer(of: pad, in: design.board.stack)))
			ValueRow(title: "X", value: millimeters(pad.at.x.mm))
			ValueRow(title: "Y", value: millimeters(pad.at.y.mm))
		} else {
			ValueRow(title: "Count", value: "\(validRefs.count)")
		}
		ValueRow(title: "Net", value: netName)
	}
}

@MainActor
struct TracesInspector: View {
	@Binding var traces: [Trace]
	var indices: [Int]
	var nets: [Net]
	var stack: Stack
	@FocusState.Binding var focus: Property?

	var body: some View {
		ValueRow(title: "Object", value: indices.count == 1 ? "Trace" : "Traces")
		if indices.count > 1 { ValueRow(title: "Count", value: "\(indices.count)") }
		LengthRow(
			title: "Width",
			value: $traces.shared(indices, \.width),
			range: 0.01 ... 50.0,
			property: .width,
			focus: $focus
		)
		LayerChoice(title: "Layer", layer: $traces.shared(indices, \.layer), stack: stack)
		NetChoice(net: $traces.shared(indices, \.net), nets: nets)
		ValueRow(
			title: "Length",
			value: millimeters(indices.reduce(0.0) { $0 + length(from: traces[$1].start, to: traces[$1].end) })
		)
	}
}

@MainActor
struct ViasInspector: View {
	@Binding var vias: [Via]
	var indices: [Int]
	var nets: [Net]
	var stack: Stack
	@FocusState.Binding var focus: Property?

	var body: some View {
		ValueRow(title: "Object", value: indices.count == 1 ? "Via" : "Vias")
		if indices.count > 1 { ValueRow(title: "Count", value: "\(indices.count)") }
		LengthRow(
			title: "Drill",
			value: $vias.shared(indices, \.drill),
			range: 0.01 ... 20.0,
			property: .drill,
			focus: $focus
		)
		LengthRow(
			title: "Pad",
			value: $vias.shared(indices, \.pad),
			range: 0.01 ... 20.0,
			property: .pad,
			focus: $focus
		)
		LayerChoice(title: "From", layer: $vias.shared(indices, \.from), stack: stack)
		LayerChoice(title: "To", layer: $vias.shared(indices, \.to), stack: stack)
		NetChoice(net: $vias.shared(indices, \.net), nets: nets)
		if indices.count == 1, let index = indices.first {
			PositionRows(at: $vias[index, or: vias[index]].at, focus: $focus)
		}
	}
}

@MainActor
struct HolesInspector: View {
	@Binding var holes: [Hole]
	var indices: [Int]
	@FocusState.Binding var focus: Property?

	var body: some View {
		ValueRow(title: "Object", value: indices.count == 1 ? "Hole" : "Holes")
		if indices.count > 1 { ValueRow(title: "Count", value: "\(indices.count)") }
		LengthRow(
			title: "Drill",
			value: $holes.shared(indices, \.diameter),
			range: 0.01 ... 50.0,
			property: .diameter,
			focus: $focus
		)
		if indices.count == 1, let index = indices.first {
			PositionRows(at: $holes[index, or: holes[index]].at, focus: $focus)
		}
	}
}

@MainActor
struct FootprintInspector: View {
	@Binding var footprint: Footprint
	@Binding var reference: String
	@Binding var value: String
	var stack: Stack
	@FocusState.Binding var focus: Property?

	var body: some View {
		ValueRow(title: "Device", value: footprint.device.name)
		ValueRow(title: "Package", value: footprint.package.name)
		if let component = footprint.component { ValueRow(title: "Part", value: component.name) }
		TextRow(
			title: "Ref",
			prompt: "R1",
			text: $reference,
			property: .reference,
			focus: $focus
		)
		TextRow(title: "Value", text: $value, property: .value, focus: $focus)
		ChoiceRow(title: "Side", value: $footprint.flipped) {
			Text(stack.name(of: stack.top)).tag(false)
			Text(stack.name(of: stack.bottom)).tag(true)
		}
		RotationChoice(rotation: Binding($footprint.rotation))
		PositionRows(at: $footprint.at, focus: $focus)
		ValueRow(title: "Pads", value: "\(footprint.pads.count)")
		ToggleRow(title: "BOM", label: "Include", value: $footprint.inBOM)
	}
}

@MainActor
struct FootprintsInspector: View {
	@Binding var design: Design
	var indices: [Int]
	var stack: Stack
	@FocusState.Binding var focus: Property?

	var body: some View {
		let footprints = design.board.footprints
		let value = $design.value(of: indices.map(Ref.footprint))
		ValueRow(title: "Device", value: indices.map { footprints[$0].device.name }.shared ?? "Mixed")
		ValueRow(title: "Package", value: indices.map { footprints[$0].package.name }.shared ?? "Mixed")
		ValueRow(title: "Count", value: "\(indices.count)")
		TextRow(
			title: "Value",
			prompt: value.wrappedValue == nil ? "Mixed" : "",
			text: value.orEmpty,
			property: .value,
			focus: $focus
		)
		ChoiceRow(title: "Side", value: $design.board.footprints.shared(indices, \.flipped)) {
			Text(stack.name(of: stack.top)).tag(Bool?.some(false))
			Text(stack.name(of: stack.bottom)).tag(Bool?.some(true))
		}
		RotationChoice(rotation: $design.board.footprints.shared(indices, \.rotation))
		ChoiceRow(title: "BOM", value: $design.board.footprints.shared(indices, \.inBOM)) {
			Text("Include").tag(Bool?.some(true))
			Text("Exclude").tag(Bool?.some(false))
		}
	}
}

@MainActor
struct LayerChoice: View {
	var title: String
	@Binding var layer: Int?
	var stack: Stack

	var body: some View {
		ChoiceRow(title: title, value: $layer) {
			ForEach(stack.signals, id: \.self) { layer in
				Text(stack.name(of: layer)).tag(Int?.some(layer))
			}
		}
	}
}

@MainActor
struct NetChoice: View {
	@Binding var net: Net.ID??
	var nets: [Net]

	var body: some View {
		ChoiceRow(title: "Net", value: $net) {
			Text("None").tag(Net.ID??.some(nil))
			ForEach(nets) { net in
				Text(net.name).tag(Net.ID??.some(net.id))
			}
		}
	}
}

@MainActor
struct RotationChoice: View {
	@Binding var rotation: Rotation?

	var body: some View {
		ChoiceRow(title: "Turned", value: $rotation) {
			ForEach(Rotation.allCases, id: \.self) { rotation in
				Text("\(rotation.degrees)°").tag(Rotation?.some(rotation))
			}
		}
	}
}
