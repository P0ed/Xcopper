import SwiftUI

@MainActor
struct LayoutSideBar: View {
	@Binding var design: Design
	@Binding var state: LayoutState
	@Binding var sheet: Sheet?
	var operations: Operations

	private var stack: Stack { design.board.stack }

	var body: some View {
		ScrollView(.vertical) {
			VStack(alignment: .leading, spacing: 12.0) {
				Panel(title: "Nets") {
					NetRow(
						name: "None",
						color: .secondary,
						selected: state.net == nil,
						select: { state.net = nil }
					)
					ForEach(design.nets) { net in
						NetRow(
							name: net.name,
							color: Palette.color(of: net.id),
							selected: state.net == net.id,
							select: { state.net = net.id },
							remove: { operations.removeNet(net.id) }
						)
					}
					HStack {
						Button("Add", systemImage: "plus") { sheet = .net }
						Spacer()
						Button("Assign", systemImage: "link") { operations.assignNet(state.net) }
							.disabled(state.selection.isEmpty)
					}
					.buttonStyle(.borderless)
					.padding(.top, 2.0)
				}

				if !stack.internals.isEmpty {
					Panel(title: "Planes") {
						ForEach(Array(stack.internals), id: \.self) { layer in
							PlaneRow(
								layer: layer,
								stack: stack,
								nets: design.nets,
								plane: design.board.plane(layer),
								select: { net in operations.setPlane(net, on: layer) }
							)
						}
					}
				}

				Panel(title: "Route") {
					GridPicker(title: "Width", value: $state.traceWidth, options: Nm.widths)
					GridPicker(title: "Snap", value: $state.snap, options: Nm.snapGrids)
					GridPicker(title: "Grid", value: $state.grid, options: Nm.displayGrids)
				}

				Panel(title: "Place") {
					Button("Footprint…", systemImage: "square.grid.3x3.square") {
						sheet = .footprint
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
		default: "\(spec.kind.name)-\(spec.pins)"
		}
	}
}

@MainActor
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
			Picker("", selection: Binding(get: { plane }, set: { net in select(net) })) {
				Text("None").tag(Net.ID?.none)
				ForEach(nets) { net in
					Text(net.name).tag(Net.ID?.some(net.id))
				}
			}
			.labelsHidden()
		}
	}
}
