import SwiftUI

@MainActor
struct LayoutInspector: View {
	@Binding var design: Design
	var selection: Set<Ref>
	@FocusState.Binding var focus: Property?

	private var board: Board { design.board }

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
	private func properties(of ref: Ref) -> some View {
		switch ref {
		case let .module(id):
			ModuleInspector(design: $design, id: id, layout: true, focus: $focus)
		case let .trace(index) where board.traces.indices.contains(index):
			TraceInspector(
				trace: $design.board.traces[index, or: board.traces[index]],
				nets: design.nets,
				stack: board.stack,
				focus: $focus
			)
		case let .via(index) where board.vias.indices.contains(index):
			ViaInspector(
				via: $design.board.vias[index, or: board.vias[index]],
				nets: design.nets,
				stack: board.stack,
				focus: $focus
			)
		case let .hole(index) where board.holes.indices.contains(index):
			HoleInspector(
				hole: $design.board.holes[index, or: board.holes[index]],
				focus: $focus
			)
		case let .footprint(index) where board.footprints.indices.contains(index):
			FootprintInspector(
				footprint: $design.board.footprints[index, or: board.footprints[index]],
				reference: $design.reference(of: Ref.footprint(index)),
				value: $design.value(of: Ref.footprint(index)).orEmpty,
				stack: board.stack,
				focus: $focus
			)
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
			FootprintsInspector(
				design: $design,
				indices: indices.filter { board.footprints.indices.contains($0) },
				stack: board.stack,
				focus: $focus
			)
		case .module:
			EmptyView()
		}
	}
}

@MainActor
struct TraceInspector: View {
	@Binding var trace: Trace
	var nets: [Net]
	var stack: Stack
	@FocusState.Binding var focus: Property?

	var body: some View {
		ValueRow(title: "Object", value: "Trace")
		LengthRow(
			title: "Width",
			value: Binding($trace.width),
			range: 0.01 ... 50.0,
			property: .width,
			focus: $focus
		)
		LayerChoice(title: "Layer", layer: Binding($trace.layer), stack: stack)
		NetChoice(net: Binding($trace.net), nets: nets)
		ValueRow(title: "Length", value: millimeters(length(from: trace.start, to: trace.end)))
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
		ValueRow(title: "Object", value: "Traces")
		ValueRow(title: "Count", value: "\(indices.count)")
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
struct ViaInspector: View {
	@Binding var via: Via
	var nets: [Net]
	var stack: Stack
	@FocusState.Binding var focus: Property?

	var body: some View {
		ValueRow(title: "Object", value: "Via")
		LengthRow(
			title: "Drill",
			value: Binding($via.drill),
			range: 0.01 ... 20.0,
			property: .drill,
			focus: $focus
		)
		LengthRow(
			title: "Pad",
			value: Binding($via.pad),
			range: 0.01 ... 20.0,
			property: .pad,
			focus: $focus
		)
		LayerChoice(title: "From", layer: Binding($via.from), stack: stack)
		LayerChoice(title: "To", layer: Binding($via.to), stack: stack)
		NetChoice(net: Binding($via.net), nets: nets)
		PositionRows(at: $via.at, focus: $focus)
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
		ValueRow(title: "Object", value: "Vias")
		ValueRow(title: "Count", value: "\(indices.count)")
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
	}
}

@MainActor
struct HoleInspector: View {
	@Binding var hole: Hole
	@FocusState.Binding var focus: Property?

	var body: some View {
		ValueRow(title: "Object", value: "Hole")
		LengthRow(
			title: "Drill",
			value: Binding($hole.diameter),
			range: 0.01 ... 50.0,
			property: .diameter,
			focus: $focus
		)
		PositionRows(at: $hole.at, focus: $focus)
	}
}

@MainActor
struct HolesInspector: View {
	@Binding var holes: [Hole]
	var indices: [Int]
	@FocusState.Binding var focus: Property?

	var body: some View {
		ValueRow(title: "Object", value: "Holes")
		ValueRow(title: "Count", value: "\(indices.count)")
		LengthRow(
			title: "Drill",
			value: $holes.shared(indices, \.diameter),
			range: 0.01 ... 50.0,
			property: .diameter,
			focus: $focus
		)
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
