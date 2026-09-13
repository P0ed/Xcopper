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

					Panel(title: "Globals") {
						GridPicker(title: "Gap", value: draft.clearance,
							options: Set(µm.clearances + [draft.wrappedValue.clearance]).sorted())
						GridPicker(title: "Trace width", value: draft.traceWidth,
							options: Set(µm.traceWidths + [draft.wrappedValue.traceWidth]).sorted())
						GridPicker(title: "Via drill", value: draft.viaDrill, options: [400, 500])
						GridPicker(title: "Via pad", value: draft.viaPad, options: [800, 900, 1_000])
					}
			}
			.frame(width: 240.0)
		}
	}
}
