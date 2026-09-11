import SwiftUI

@MainActor
struct BoardDialog: View {
	var size: Size
	var stack: Stack
	var rules: Rules
	var solderMask: Bool
	var confirm: (Size, Stack, Rules, Bool) -> Void

	@State private var chosen: Size?
	@State private var selected: Stack?
	@State private var selectedRules: Rules?
	@State private var selectedSolderMask: Bool?
	@FocusState private var focus: Property?

	private var stackup: Stack { selected ?? stack }
	private var draft: Binding<Rules> {
		Binding(get: { selectedRules ?? rules }, set: { selectedRules = $0 })
	}
	private var validVias: Bool {
		let rules = draft.wrappedValue
		return rules.viaDrill > 0 && rules.viaPad > rules.viaDrill
	}

	var body: some View {
		Dialog(
			action: "Apply",
			isValid: chosen != nil && validVias,
			confirm: {
				if let chosen { confirm(chosen, stackup, draft.wrappedValue, selectedSolderMask ?? solderMask) }
			}
		) {
			VStack(spacing: 12.0) {
				SizeFields(size: size, limit: 500 * .mm, value: $chosen)

				Picker("Stackup", selection: Binding(get: { stackup }, set: { selected = $0 })) {
					ForEach(Stack.allCases, id: \.self) { stack in
						Text(stack.name).tag(stack)
					}
				}
				.pickerStyle(.segmented)
				.labelsHidden()

				Text(stackup.summary)
					.font(.caption)
					.foregroundStyle(.secondary)

				Toggle("Solder mask", isOn: Binding(
					get: { selectedSolderMask ?? solderMask },
					set: { selectedSolderMask = $0 }
				))
				.toggleStyle(.checkbox)

				Panel(title: "Vias") {
					LengthRow(title: "Drill", value: Binding(draft.viaDrill),
						range: 0.01 ... 20.0, property: .drill, focus: $focus)
					LengthRow(title: "Pad", value: Binding(draft.viaPad),
						range: 0.01 ... 20.0, property: .pad, focus: $focus)
					Text(validVias ? "Applies to every via on this board." : "The pad must be larger than the drill.")
						.font(.caption)
						.foregroundStyle(validVias ? Color.secondary : .orange)
				}
			}
			.frame(width: 240.0)
		}
	}
}
