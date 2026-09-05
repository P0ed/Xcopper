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
				stack: board.stack,
				focus: $focus
			)
		default:
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
			value: $trace.width,
			range: 0.01 ... 50.0,
			property: .width,
			focus: $focus
		)
		LayerChoice(title: "Layer", layer: $trace.layer, stack: stack)
		NetChoice(net: $trace.net, nets: nets)
		ValueRow(title: "Length", value: millimeters(length(from: trace.start, to: trace.end)))
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
			value: $via.drill,
			range: 0.01 ... 20.0,
			property: .drill,
			focus: $focus
		)
		LengthRow(title: "Pad", value: $via.pad, range: 0.01 ... 20.0, property: .pad, focus: $focus)
		LayerChoice(title: "From", layer: $via.from, stack: stack)
		LayerChoice(title: "To", layer: $via.to, stack: stack)
		NetChoice(net: $via.net, nets: nets)
		PositionRows(at: $via.at, focus: $focus)
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
			value: $hole.diameter,
			range: 0.01 ... 50.0,
			property: .diameter,
			focus: $focus
		)
		PositionRows(at: $hole.at, focus: $focus)
	}
}

@MainActor
struct FootprintInspector: View {
	@Binding var footprint: Footprint
	var stack: Stack
	@FocusState.Binding var focus: Property?

	var body: some View {
		TextRow(
			title: "Ref",
			prompt: "R1",
			text: $footprint.reference,
			property: .reference,
			focus: $focus
		)
		TextRow(title: "Value", text: $footprint.value, property: .value, focus: $focus)
		ChoiceRow(title: "Side", value: $footprint.flipped) {
			Text(stack.name(of: stack.top)).tag(false)
			Text(stack.name(of: stack.bottom)).tag(true)
		}
		RotationChoice(rotation: $footprint.rotation)
		PositionRows(at: $footprint.at, focus: $focus)
		ValueRow(title: "Pads", value: "\(footprint.pads.count)")
	}
}

@MainActor
struct LayerChoice: View {
	var title: String
	@Binding var layer: Int
	var stack: Stack

	var body: some View {
		ChoiceRow(title: title, value: $layer) {
			ForEach(stack.signals, id: \.self) { layer in
				Text(stack.name(of: layer)).tag(layer)
			}
		}
	}
}

@MainActor
struct NetChoice: View {
	@Binding var net: Net.ID?
	var nets: [Net]

	var body: some View {
		ChoiceRow(title: "Net", value: $net) {
			Text("None").tag(Net.ID?.none)
			ForEach(nets) { net in
				Text(net.name).tag(Net.ID?.some(net.id))
			}
		}
	}
}

@MainActor
struct RotationChoice: View {
	@Binding var rotation: Rotation

	var body: some View {
		ChoiceRow(title: "Turned", value: $rotation) {
			ForEach(Rotation.allCases, id: \.self) { rotation in
				Text("\(rotation.degrees)°").tag(rotation)
			}
		}
	}
}
