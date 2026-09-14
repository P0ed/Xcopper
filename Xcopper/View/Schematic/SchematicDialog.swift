import SwiftUI

@MainActor
struct SchematicDialog: View {
	var size: Size
	var confirm: (Size) -> Void

	@State private var chosen: Size?
	@State private var unit: LengthUnit = .millimeters

	var body: some View {
		Dialog(
			action: "Apply",
			isValid: chosen != nil,
			confirm: {
				if let chosen { confirm(chosen) }
			}
		) {
			SizeFields(size: size, limit: 2_000 * .mm, value: $chosen, unit: $unit)
				.frame(width: 240.0)
		}
	}
}
