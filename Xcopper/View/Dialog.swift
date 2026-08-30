import SwiftUI

struct Dialog<Content: View>: View {
	var action: String
	var isValid: Bool = true
	var confirm: () -> Void
	var content: () -> Content
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		VStack(spacing: 16.0) {
			content()
			HStack {
				Button("Cancel") {
					dismiss()
				}
				.keyboardShortcut(.cancelAction)

				Button(action) {
					confirm()
					dismiss()
				}
				.disabled(!isValid)
				.keyboardShortcut(.defaultAction)
			}
		}
		.padding(24.0)
	}
}
