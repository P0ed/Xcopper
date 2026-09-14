import SwiftUI

@MainActor
struct BoardDialog: View {
	@State var sheet: Size
	@State var board: Size
	@State var stack: Stack
	@State var rules: Rules
	@State var solderMask: Bool
	@State var origin: Point
	@State private var unit: LengthUnit = .millimeters
	@FocusState private var focus: Property?
	var confirm: (Size, Size, Stack, Rules, Bool, Point) -> Void

	init(
		sheet: Size, board: Size, stack: Stack, rules: Rules, solderMask: Bool, origin: Point,
		confirm: @escaping (Size, Size, Stack, Rules, Bool, Point) -> Void
	) {
		self.sheet = sheet
		self.board = board
		self.stack = stack
		self.rules = rules
		self.solderMask = solderMask
		self.origin = origin
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
					solderMask,
					origin
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
					LengthRow(title: "X", value: Binding($origin.x), unit: unit, property: .x, focus: $focus)
					LengthRow(title: "Y", value: Binding($origin.y), unit: unit, property: .y, focus: $focus)
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
					}
			}
			.frame(width: 240.0)
		}
	}
}
