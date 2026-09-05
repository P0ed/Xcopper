import SwiftUI

@MainActor
struct LayoutSideBar: View {
	@Binding var design: Design
	@Binding var state: LayoutState
	@Binding var editor: EditorState
	var operations: Operations

	@FocusState private var focus: Property?

	private var stack: Stack { design.board.stack }

	var body: some View {
		ScrollView(.vertical) {
			VStack(alignment: .leading, spacing: 12.0) {
				Panel(title: "Selection") {
					LayoutInspector(design: $design, selection: state.selection, focus: $focus)
					CounterpartButton(operations: operations)
				}

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
						Button("Add", systemImage: "plus") { editor.sheet = .net }
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

				Panel(title: "Design rules") {
					LengthRow(
						title: "Gap",
						value: $design.board.rules.clearance,
						range: 0.01 ... 5.0,
						property: .clearance,
						focus: $focus
					)
					CheckList(
						violations: design.check(),
						stack: stack,
						show: operations.show
					)
				}

				Panel(title: "Route") {
					GridPicker(title: "Width", value: $state.traceWidth, options: Nm.widths)
					GridPicker(title: "Snap", value: $state.snap, options: Nm.snapGrids)
					GridPicker(title: "Grid", value: $state.grid, options: Nm.displayGrids)
				}

				Panel(title: "Place") {
					Button("Footprint…", systemImage: "square.grid.3x3.square") {
						editor.sheet = .footprint
					}
					.buttonStyle(.borderless)
					Text(state.spec.summary)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
			.padding(12.0)
		}
		.navigationSplitViewColumnWidth(min: 190.0, ideal: 230.0, max: 300.0)
		.onChange(of: focus) { _, field in editor.editing = field != nil }
		.onChange(of: editor.editing) { _, editing in if !editing { focus = nil } }
		.onDisappear { editor.editing = false }
	}
}

@MainActor
struct CheckList: View {
	var violations: [Violation]
	var stack: Stack
	var show: (Violation) -> Void

	private static let shown = 12

	var body: some View {
		if violations.isEmpty {
			Text("Nothing wrong")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
		ForEach(Array(violations.prefix(Self.shown).enumerated()), id: \.offset) { _, violation in
			ViolationRow(violation: violation, stack: stack, show: { show(violation) })
		}
		if violations.count > Self.shown {
			Text("and \(violations.count - Self.shown) more")
				.font(.caption)
				.foregroundStyle(.tertiary)
				.padding(.horizontal, 6.0)
		}
	}
}

@MainActor
struct ViolationRow: View {
	var violation: Violation
	var stack: Stack
	var show: () -> Void

	var body: some View {
		HStack(spacing: 6.0) {
			Image(systemName: violation.kind.systemImage)
				.foregroundStyle(violation.kind.color)
				.frame(width: 10.0)
			Text(violation.text).lineLimit(1)
			Spacer(minLength: 0.0)
			if let layer = violation.layer {
				Text(stack.shortName(of: layer))
					.foregroundStyle(Palette.color(of: layer, in: stack))
			}
		}
		.font(.caption)
		.padding(.horizontal, 6.0)
		.padding(.vertical, 3.0)
		.contentShape(.rect)
		.onTapGesture(perform: show)
	}
}

extension Violation.Kind {

	var color: Color {
		switch self {
		case .short: Palette.violation
		case .clearance, .hole, .edge: .orange
		case .unrouted: .secondary
		}
	}

	var systemImage: String {
		switch self {
		case .short: "exclamationmark.triangle.fill"
		case .clearance, .hole, .edge: "exclamationmark.circle.fill"
		case .unrouted: "point.3.connected.trianglepath.dotted"
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
				.frame(width: .captionWidth, alignment: .leading)
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
