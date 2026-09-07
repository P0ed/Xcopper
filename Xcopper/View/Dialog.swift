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

@MainActor
struct FindDialog: View {
	@Binding var query: String
	var confirm: (String) -> Void

	var body: some View {
		Dialog(
			action: "Find",
			isValid: !query.trimmingWhitespace.isEmpty,
			confirm: { confirm(query.trimmingWhitespace) }
		) {
			TextField("Reference or value", text: $query)
				.frame(width: 180.0)
		}
	}
}

enum LengthUnit: CaseIterable, Identifiable {
	case millimeters, inches

	var id: Self { self }
	var label: String { self == .millimeters ? "mm" : "in" }
}

@MainActor
struct SizeFields: View {
	var size: Size
	var limit: Nm
	@Binding var value: Size?

	@State private var width: String = ""
	@State private var height: String = ""
	@State private var unit: LengthUnit = .millimeters

	var body: some View {
		VStack(spacing: 12.0) {
			Picker("Units", selection: unitBinding) {
				ForEach(LengthUnit.allCases) { unit in
					Text(unit.label).tag(unit)
				}
			}
			.pickerStyle(.segmented)

			HStack {
				TextField(format(size.width, as: unit), text: $width)
					.frame(width: 88.0)
					.multilineTextAlignment(.trailing)
				Text("×")
				TextField(format(size.height, as: unit), text: $height)
					.frame(width: 88.0)
					.multilineTextAlignment(.trailing)
				Text(unit.label)
			}
		}
		.onAppear { publish() }
		.onChange(of: width) { _, _ in publish() }
		.onChange(of: height) { _, _ in publish() }
	}

	private var unitBinding: Binding<LengthUnit> {
		Binding(
			get: { unit },
			set: { newUnit in
				guard newUnit != unit else { return }
				let parsedWidth = width.isEmpty ? nil : parse(width, as: unit)
				let parsedHeight = height.isEmpty ? nil : parse(height, as: unit)
				guard width.isEmpty || parsedWidth != nil, height.isEmpty || parsedHeight != nil else { return }

				unit = newUnit
				if let parsedWidth { width = format(parsedWidth, as: newUnit) }
				if let parsedHeight { height = format(parsedHeight, as: newUnit) }
			}
		)
	}

	private func publish() {
		guard let w = length(width, or: size.width), let h = length(height, or: size.height),
			w > 0, h > 0, w <= limit, h <= limit
		else {
			value = nil
			return
		}
		value = Size(width: Int(w), height: Int(h))
	}

	private func length(_ text: String, or fallback: Nm) -> Nm? {
		text.isEmpty ? fallback : parse(text, as: unit)
	}

	private func parse(_ text: String, as unit: LengthUnit) -> Nm? {
		Double(text.replacingOccurrences(of: ",", with: ".")).map { value in
			unit == .millimeters ? .mm(value) : .inches(value)
		}
	}

	private func format(_ length: Nm, as unit: LengthUnit) -> String {
		let value = unit == .millimeters ? length.mm : length.inches
		var text = String(format: unit == .millimeters ? "%.6f" : "%.8f", value)
		while text.last == "0" { text.removeLast() }
		if text.last == "." { text.removeLast() }
		return text
	}
}
