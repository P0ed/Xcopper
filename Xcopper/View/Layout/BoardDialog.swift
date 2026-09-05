import SwiftUI

private enum BoardUnit: CaseIterable, Identifiable {
	case millimeters, inches

	var id: Self { self }
	var label: String { self == .millimeters ? "mm" : "in" }
}

@MainActor
struct BoardDialog: View {
	var size: Size
	var stack: Stack
	var confirm: (Size, Stack) -> Void

	@State var width: String = ""
	@State var height: String = ""
	@State var selected: Stack?
	@State private var unit: BoardUnit = .millimeters

	private var chosen: Stack { selected ?? stack }
	private var w: Nm? { width.isEmpty ? Nm(size.width) : parse(width, as: unit) }
	private var h: Nm? { height.isEmpty ? Nm(size.height) : parse(height, as: unit) }

	private var isValid: Bool {
		guard let w, let h else { return false }
		return w > 0 && h > 0 && w <= .mm(500) && h <= .mm(500)
	}

	var body: some View {
		Dialog(
			action: "Apply",
			isValid: isValid,
			confirm: {
				if let w, let h {
					confirm(Size(width: Int(w), height: Int(h)), chosen)
				}
			}
		) {
			VStack(spacing: 12.0) {
				Picker("Units", selection: unitBinding) {
					ForEach(BoardUnit.allCases) { unit in
						Text(unit.label).tag(unit)
					}
				}
				.pickerStyle(.segmented)

				HStack {
					TextField(format(Nm(size.width), as: unit), text: $width)
						.frame(width: 88.0)
						.multilineTextAlignment(.trailing)
					Text("×")
					TextField(format(Nm(size.height), as: unit), text: $height)
						.frame(width: 88.0)
						.multilineTextAlignment(.trailing)
					Text(unit.label)
				}
				Picker("Stackup", selection: Binding(get: { chosen }, set: { selected = $0 })) {
					ForEach(Stack.allCases, id: \.self) { stack in
						Text(stack.name).tag(stack)
					}
				}
				.pickerStyle(.segmented)
				.labelsHidden()

				Text(chosen.summary)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			.frame(width: 240.0)
		}
	}

	private var unitBinding: Binding<BoardUnit> {
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

	private func parse(_ text: String, as unit: BoardUnit) -> Nm? {
		Double(text.replacingOccurrences(of: ",", with: ".")).map { value in
			unit == .millimeters ? .mm(value) : .inches(value)
		}
	}

	private func format(_ length: Nm, as unit: BoardUnit) -> String {
		let value = unit == .millimeters ? length.mm : length.inches
		var text = String(format: unit == .millimeters ? "%.6f" : "%.8f", value)
		while text.last == "0" { text.removeLast() }
		if text.last == "." { text.removeLast() }
		return text
	}
}
