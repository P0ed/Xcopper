import SwiftUI

@MainActor
struct PreviewSideBar: View {
	var board: Board
	@Binding var state: PreviewState

	var body: some View {
		ScrollView(.vertical) {
			VStack(alignment: .leading, spacing: 12.0) {
				Panel(title: "View") {
					LazyVGrid(columns: [GridItem(.adaptive(minimum: 62.0), spacing: 4.0)], spacing: 4.0) {
						ForEach(Standpoint.allCases) { stand in
							Button(stand.name) { state.look(from: stand, at: board) }
								.buttonStyle(.bordered)
								.controlSize(.small)
						}
					}
					Button("Fit", systemImage: "arrow.up.left.and.down.right.magnifyingglass") {
						state.frame(board)
					}
					.buttonStyle(.borderless)
					.padding(.top, 2.0)
				}

				Panel(title: "Finish") {
					Picker("Mask", selection: $state.finish.mask) {
						ForEach(Mask.allCases) { mask in
							Text(mask.name).tag(mask)
						}
					}
					Picker("Pads", selection: $state.finish.plating) {
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

/// What one part is and how tall it stands, the two things the flat views
/// cannot tell you
@MainActor
struct PartRow: View {
	var footprint: Footprint

	/// How tall the part stands, or a dash for one the board only carries the
	/// pads of, which stands on the panel rather than on the board
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
