import SwiftUI

extension EditorView {

	var sidebar: some View {
		ScrollView(.vertical) {
			VStack(alignment: .leading, spacing: 12.0) {
				section("Nets") {
					NetRow(
						name: "None",
						color: .secondary,
						selected: state.net == nil,
						select: { state.net = nil }
					)
					ForEach(board.nets) { net in
						NetRow(
							name: net.name,
							color: Palette.color(of: net.id),
							selected: state.net == net.id,
							select: { state.net = net.id },
							remove: { operations.removeNet(net.id) }
						)
					}
					HStack {
						Button("Add", systemImage: "plus") { state.netDialogPresented = true }
						Spacer()
						Button("Assign", systemImage: "link") { operations.assignNet(state.net) }
							.disabled(state.selection.isEmpty)
					}
					.buttonStyle(.borderless)
					.padding(.top, 2.0)
				}

				if !board.stack.internals.isEmpty {
					section("Planes") {
						ForEach(Array(board.stack.internals), id: \.self) { layer in
							PlaneRow(
								layer: layer,
								stack: board.stack,
								nets: board.nets,
								plane: board.plane(layer),
								select: { net in operations.setPlane(net, on: layer) }
							)
						}
					}
				}

				section("Route") {
					picker("Width", value: $state.traceWidth, options: Nm.widths)
					picker("Grid", value: $state.grid, options: Nm.grids)
				}

				section("Place") {
					Button("Footprint…", systemImage: "square.grid.3x3.square") {
						state.footprintDialogPresented = true
					}
					.buttonStyle(.borderless)
					Text(specSummary)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
			.padding(12.0)
		}
		.navigationSplitViewColumnWidth(min: 190.0, ideal: 210.0, max: 280.0)
	}

	private var specSummary: String {
		let spec = state.spec
		return switch spec.kind {
		case .chip: "Chip \(spec.chip.name)"
		case .sot23: "SOT-23"
		case .header: "Header \(spec.rows)×\(spec.pins)"
		case .qfp: "QFP-\(spec.pins) \(spec.pitch.label)mm"
		default: "\(spec.kind.name)-\(spec.pins)"
		}
	}

	private func section<Content: View>(
		_ title: String,
		@ViewBuilder content: () -> Content
	) -> some View {
		VStack(alignment: .leading, spacing: 4.0) {
			Text(title)
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
			content()
		}
	}

	private func picker(_ title: String, value: Binding<Nm>, options: [Nm]) -> some View {
		HStack(spacing: 6.0) {
			Text(title)
				.foregroundStyle(.secondary)
				.frame(width: 40.0, alignment: .leading)
			Picker("", selection: value) {
				ForEach(options, id: \.self) { option in
					Text("\(option.label) mm").tag(option)
				}
			}
			.labelsHidden()
		}
	}
}

struct NetRow: View {
	var name: String
	var color: Color
	var selected: Bool
	var select: () -> Void = ø
	var remove: (() -> Void)?

	var body: some View {
		HStack(spacing: 6.0) {
			Circle().fill(color).frame(width: 10.0, height: 10.0)
			Text(name).lineLimit(1)
			Spacer(minLength: 0.0)
			if let remove {
				Button("Delete", systemImage: "xmark", action: remove)
					.buttonStyle(.borderless)
					.labelStyle(.iconOnly)
					.foregroundStyle(.tertiary)
			}
		}
		.padding(.horizontal, 6.0)
		.padding(.vertical, 3.0)
		.background(selected ? Color.accentColor.opacity(0.25) : .clear, in: .rect(cornerRadius: 5.0))
		.contentShape(.rect)
		.onTapGesture(perform: select)
	}
}

struct PlaneRow: View {
	var layer: Int
	var stack: Stack
	var nets: [Net]
	var plane: Net.ID?
	var select: (Net.ID?) -> Void

	var body: some View {
		HStack(spacing: 6.0) {
			Text(stack.name(of: layer))
				.foregroundStyle(Palette.color(of: layer, in: stack))
				.frame(width: 34.0, alignment: .leading)
			Picker("", selection: Binding(get: { plane }, set: select)) {
				Text("None").tag(Net.ID?.none)
				ForEach(nets) { net in
					Text(net.name).tag(Net.ID?.some(net.id))
				}
			}
			.labelsHidden()
		}
	}
}
