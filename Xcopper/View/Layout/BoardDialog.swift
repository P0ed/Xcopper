import SwiftUI

@MainActor
struct BoardDialog: View {
	@State var sheet: Size
	@State var board: Size
	@State var stack: Stack
	@State var rules: Rules
	@State var solderMask: Bool
	@State private var unit: LengthUnit = .millimeters
	@FocusState private var focus: Property?
	var confirm: (Size, Size, Stack, Rules, Bool) -> Void

	init(
		sheet: Size, board: Size, stack: Stack, rules: Rules, solderMask: Bool,
		confirm: @escaping (Size, Size, Stack, Rules, Bool) -> Void
	) {
		self.sheet = sheet
		self.board = board
		self.stack = stack
		self.rules = rules
		self.solderMask = solderMask
		self.confirm = confirm
		self.unit = unit
		self.focus = focus
	}

	var body: some View {
		Dialog(
			action: "Apply",
			isValid: rules.isValid,
			confirm: {
				confirm(
					sheet,
					board,
					stack,
					rules,
					solderMask
				)
			}
		) {
			VStack(spacing: 12.0) {
				Picker("Units", selection: $unit) {
					ForEach(LengthUnit.allCases) { unit in
						Text(unit.label).tag(unit)
					}
				}
				.pickerStyle(.segmented)
				Panel(title: "Sheet") {
					LengthRow(title: "Width", value: Binding($sheet.width), unit: unit, property: .value, focus: $focus)
					LengthRow(title: "Height", value: Binding($sheet.height), unit: unit, property: .value, focus: $focus)
				}
				Panel(title: "Board") {
					LengthRow(title: "Width", value: Binding($board.width), unit: unit, property: .value, focus: $focus)
					LengthRow(title: "Height", value: Binding($board.height), unit: unit, property: .value, focus: $focus)
				}

				Picker("Stackup", selection: $stack) {
					ForEach(Stack.allCases, id: \.self) { stack in
						Text(stack.name).tag(stack)
					}
				}
				.pickerStyle(.segmented)
				.labelsHidden()

				Text(stack.summary)
					.font(.caption)
					.foregroundStyle(.secondary)

				Toggle("Solder mask", isOn: $solderMask)
				.toggleStyle(.checkbox)

				Panel(title: "Globals") {
					ValuePicker(title: "Gap", value: $rules.clearance,
						options: Set(µm.clearances + [rules.clearance]).sorted())
					ValuePicker(title: "Trace width", value: $rules.traceWidth,
						options: Set(µm.traceWidths + [rules.traceWidth]).sorted())
					ValuePicker(title: "Via drill", value: $rules.viaDrill, options: [400, 500])
					ValuePicker(title: "Via pad", value: $rules.viaPad, options: [800, 900, 1_000])
					ValuePicker(title: "Min trace length", value: $rules.minTraceLength,
						options: [(0, "None"), (100, "0.1 mm"), (300, "0.3 mm")])
				}
			}
			.frame(width: 240.0)
		}
	}
}
