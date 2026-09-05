import SwiftUI

@MainActor
struct PreviewSideBar: View {
	var board: Board
	@Binding var state: PreviewState

	var body: some View {
		ScrollView(.vertical) {
			VStack(alignment: .leading, spacing: 12.0) {
				Panel(title: "Finish") {
					ChoiceRow(title: "Mask", value: $state.finish.mask) {
						ForEach(Mask.allCases) { mask in
							Text(mask.name).tag(mask)
						}
					}
					ChoiceRow(title: "Pads", value: $state.finish.plating) {
						ForEach(Plating.allCases) { plating in
							Text(plating.name).tag(plating)
						}
					}
					GridPicker(
						title: "Core",
						value: $state.finish.thickness,
						options: Nm.thicknesses
					)
				}

				Panel(title: "Show") {
					Toggle("Copper", isOn: $state.finish.copper)
					Toggle("Components", isOn: $state.finish.components)
				}
				.toggleStyle(.checkbox)

				Panel(title: "Stuffed") {
					if board.footprints.isEmpty {
						Text("Nothing placed yet")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
					ForEach(Array(board.footprints.enumerated()), id: \.offset) { _, footprint in
						PartRow(footprint: footprint)
					}
				}
			}
			.padding(12.0)
		}
		.navigationSplitViewColumnWidth(min: 190.0, ideal: 210.0, max: 280.0)
	}
}

@MainActor
struct PartRow: View {
	var footprint: Footprint

	private var height: String {
		let package = footprint.package
		return package.stands ? "\(package.height.label) mm" : "—"
	}

	var body: some View {
		HStack(spacing: 6.0) {
			RoundedRectangle(cornerRadius: 2.0)
				.fill(footprint.package.color.color)
				.frame(width: 10.0, height: 10.0)
			Text(footprint.reference).lineLimit(1)
			Spacer(minLength: 0.0)
			Text(footprint.flipped ? "B" : "T")
				.foregroundStyle(.tertiary)
			Text(height)
				.foregroundStyle(.secondary)
		}
		.font(.caption.monospacedDigit())
		.padding(.horizontal, 6.0)
		.padding(.vertical, 2.0)
	}
}
