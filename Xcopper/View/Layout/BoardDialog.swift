import SwiftUI

@MainActor
struct BoardDialog: View {
	var size: Size
	var stack: Stack
	var confirm: (Size, Stack) -> Void

	@State private var chosen: Size?
	@State private var selected: Stack?

	private var stackup: Stack { selected ?? stack }

	var body: some View {
		Dialog(
			action: "Apply",
			isValid: chosen != nil,
			confirm: {
				if let chosen { confirm(chosen, stackup) }
			}
		) {
			VStack(spacing: 12.0) {
				SizeFields(size: size, limit: .mm(500), value: $chosen)

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
			}
			.frame(width: 240.0)
		}
	}
}
