import SwiftUI

@MainActor
struct SchematicSideBar: View {
	@Binding var design: Design
	@Binding var state: SchematicState
	@Binding var editor: EditorState
	var operations: Operations

	/// Read back out of the drawing every time, so it can never be stale
	private var netlist: Netlist { Netlist(design.schematic) }

	var body: some View {
		ScrollView(.vertical) {
			VStack(alignment: .leading, spacing: 12.0) {
				Panel(title: "Sheet") {
					GridPicker(title: "Grid", value: $state.grid, options: Nm.sheetGrids)
				}

				Panel(title: "Place") {
					Button("Symbol…", systemImage: "square.on.circle") { editor.sheet = .symbol }
						.buttonStyle(.borderless)
					Text(specSummary)
						.font(.caption)
						.foregroundStyle(.secondary)
					Button("Label…", systemImage: "tag") { editor.sheet = .label }
						.buttonStyle(.borderless)
						.padding(.top, 2.0)
					Text(state.label)
						.font(.caption)
						.foregroundStyle(.secondary)
				}

				Panel(title: "Nets on this sheet") {
					let groups = netlist.groups
						.filter { !$0.nodes.isEmpty }
						.sorted { ($0.name ?? "~", $0.nodes.count) < ($1.name ?? "~", $1.nodes.count) }

					if groups.isEmpty {
						Text("Nothing wired yet")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
					ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
						NetRow(
							name: "\(group.name ?? "unnamed")  ·  \(group.nodes.count)",
							color: group.name.map(Palette.color(named:)) ?? .secondary,
							selected: false
						)
					}
				}

				Panel(title: "Board") {
					Button("Update board", systemImage: "arrow.triangle.2.circlepath") {
						operations.updateBoard()
					}
					.buttonStyle(.borderless)

					if let report = editor.report {
						ReportView(report: report)
					}
				}
			}
			.padding(12.0)
		}
		.navigationSplitViewColumnWidth(min: 190.0, ideal: 210.0, max: 280.0)
	}

	private var specSummary: String {
		let spec = state.spec
		return switch spec.kind {
		case .ic: "IC-\(spec.pins)"
		case .power, .ground: "\(spec.kind.name) \(spec.value.isEmpty ? spec.kind.defaultValue : spec.value)"
		default: spec.kind.name
		}
	}
}

@MainActor
struct ReportView: View {
	var report: Design.Report

	var body: some View {
		VStack(alignment: .leading, spacing: 2.0) {
			Text("Assigned \(report.assigned) pad\(report.assigned == 1 ? "" : "s")")
			line("New nets", report.created, .secondary)
			line("No footprint", report.missingFootprints, .orange)
			line("No pad", report.missingPins, .orange)
			line("Not in schematic", report.extraFootprints, .secondary)
		}
		.font(.caption)
		.foregroundStyle(.secondary)
		.padding(.top, 2.0)
	}

	@ViewBuilder
	private func line(_ title: String, _ items: [String], _ color: Color) -> some View {
		if !items.isEmpty {
			Text("\(title): \(items.joined(separator: ", "))")
				.foregroundStyle(color)
		}
	}
}
