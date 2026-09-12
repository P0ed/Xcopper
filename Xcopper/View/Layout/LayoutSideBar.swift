import SwiftUI

@MainActor
struct LayoutSideBar: View {
	@Binding var design: Design
	@Binding var state: LayoutState
	@Binding var editor: EditorState
	var operations: Operations

	@FocusState private var focus: Property?
	@State private var violations: [Violation] = []

	private var stack: Stack { design.board.stack }

	var body: some View {
		ScrollView(.vertical) {
			VStack(alignment: .leading, spacing: 12.0) {
				Panel(title: "Selection") {
					LayoutInspector(design: $design, selection: state.selection, focus: $focus) { ref in
						state.cancelSessions()
						state.selection = [ref]
					}
					CounterpartButton(operations: operations)
				}

				Panel(title: "Board") {
					GridPicker(
						title: "Gap",
						value: $design.board.rules.clearance,
						options: µm.clearances
					)
					CheckList(
						violations: violations,
						stack: stack,
						show: operations.show
					)
					GridPicker(title: "Trace", value: $state.traceWidth, options: µm.widths)
					GridPicker(title: "Route", value: $state.routingGrid, options: µm.routingGrids)
					GridPicker(title: "Place", value: $state.placementGrid, options: µm.placementGrids)
					GridPicker(title: "Grid", value: $state.grid, options: µm.displayGrids)

					Button(state.spec.summary, systemImage: "square.grid.3x3.square") {
						editor.sheet = .footprint
					}
					.buttonStyle(.borderless)
				}

				Panel(title: "Layers") {
					LayerRow(
						text: "Silkscreen",
						color: .primary,
						shortcut: editor.keysAvailable ? "§" : nil,
						toggle: $state.silkscreen
					)
					ForEach(Array(stack.copper), id: \.self) { layer in
						let text = stack.name(of: layer) + ": "
							+ (design.net(design.plane(layer))?.name ?? "SIG")
						let color = Palette.color(of: layer, in: stack)
						LayerRow(
							text: text,
							color: color,
							shortcut: editor.keysAvailable ? "\(layer + 1)".first : nil,
							toggle: $state[visible: layer]
						)
					}
				}

				ModulePanel(operations: operations)

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
							remove: design.isPlaneNet(net.id)
								? nil
								: { operations.removeNet(net.id) }
						)
					}
					HStack {
						Button("Add", systemImage: "plus") { editor.sheet = .net }
						Spacer()
						Button("Assign", systemImage: "link") { operations.assignNet(state.net) }
							.disabled(!operations.canAssignNet)
					}
					.buttonStyle(.borderless)
					.padding(.top, 2.0)
				}
			}
			.padding(12.0)
		}
		.navigationSplitViewColumnWidth(min: 190.0, ideal: 230.0, max: 300.0)
		.onChange(of: design, initial: true) { _, design in violations = design.check() }
		.onChange(of: focus) { _, field in editor.editing = field }
		.onChange(of: editor.editing) { _, editing in focus = editing }
		.onDisappear { editor.editing = nil }
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
struct LayerRow: View {
	var text: String
	var color: Color
	var shortcut: Character?
	@Binding var toggle: Bool

	var body: some View {
		Button {
			toggle.toggle()
		} label: {
			Label(text, systemImage: toggle ? "largecircle.fill.circle" : "circle")
				.foregroundStyle(color)
				.font(.caption)
				.padding(.horizontal, 6.0)
				.padding(.vertical, 3.0)
		}
		.buttonStyle(.borderless)
		.keyboardShortcut(shortcut.map { char in
			KeyboardShortcut(KeyEquivalent(char), modifiers: [])
		})
		.accessibilityAddTraits(toggle ? .isSelected : [])
	}
}
