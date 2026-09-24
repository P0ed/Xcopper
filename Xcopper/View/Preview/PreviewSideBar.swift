import SwiftUI

@MainActor
struct PreviewSideBar: View {
	var board: Board
	@Binding var state: PreviewState

	var body: some View {
		ScrollView(.vertical) {
			VStack(alignment: .leading, spacing: 12.0) {
				Panel(title: "Finish") {
					ValuePicker(
						title: "Mask",
						value: $state.finish.mask,
						options: [nil] + Mask.allCases.map { Optional($0) },
						label: { $0?.name ?? "None" }
					)
					ChoiceRow(title: "Pads", value: $state.finish.plating) {
						ForEach(Plating.allCases) { plating in
							Text(plating.name).tag(plating)
						}
					}
					ValuePicker(
						title: "Core",
						value: $state.finish.thickness,
						options: µm.thicknesses
					)
				}

				Panel(title: "Show") {
					Toggle("Copper", isOn: $state.finish.copper)
					Toggle("Components", isOn: $state.finish.components)
						.keyboardShortcut(.init(.init("C"), modifiers: []))
				}
				.toggleStyle(.checkbox)
			}
			.padding(12.0)
		}
		.navigationSplitViewColumnWidth(min: 190.0, ideal: 210.0, max: 280.0)
	}
}
