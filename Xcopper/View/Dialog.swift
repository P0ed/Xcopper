import SwiftUI

@MainActor
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

@MainActor
struct NetDialog: View {
	var confirm: (String) -> Void

	@State var name: String = ""

	var body: some View {
		Dialog(
			action: "Add",
			isValid: !name.trimmingWhitespace.isEmpty,
			confirm: { confirm(name.trimmingWhitespace) }
		) {
			TextField("Net name", text: $name)
				.frame(width: 180.0)
		}
	}
}

@MainActor
struct LabelDialog: View {
	@Binding var text: String
	var confirm: () -> Void

	@State var draft: String = ""

	var body: some View {
		Dialog(
			action: "Use",
			isValid: !draft.trimmingWhitespace.isEmpty,
			confirm: {
				text = draft.trimmingWhitespace
				confirm()
			}
		) {
			TextField("Net name", text: $draft)
				.frame(width: 180.0)
		}
		.onAppear { draft = text }
	}
}
