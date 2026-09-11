import SwiftUI

@MainActor
struct SchematicDialog: View {
	var size: Size
	var confirm: (Size) -> Void

	@State private var chosen: Size?

	var body: some View {
		Dialog(
			action: "Apply",
			isValid: chosen != nil,
			confirm: {
				if let chosen { confirm(chosen) }
			}
		) {
			SizeFields(size: size, limit: 2_000 * .mm, value: $chosen)
				.frame(width: 240.0)
		}
	}
}
