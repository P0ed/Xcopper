import SwiftUI

@MainActor
struct BoardDialog: View {
	var size: Size
	var stack: Stack
	var loss: (Stack) -> Int
	var confirm: (Size, Stack) -> Void

	@State var width: String = ""
	@State var height: String = ""
	@State var selected: Stack?

	private var chosen: Stack { selected ?? stack }
	private var w: Nm? { width.isEmpty ? Nm(size.width) : parse(width) }
	private var h: Nm? { height.isEmpty ? Nm(size.height) : parse(height) }

	private var isValid: Bool {
		guard let w, let h else { return false }
		return w > 0 && h > 0 && w <= .mm(500) && h <= .mm(500)
	}

	private var dropped: Int { chosen == stack ? 0 : loss(chosen) }

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
				HStack {
					TextField("\(Nm(size.width).label)", text: $width)
						.frame(width: 64.0)
						.multilineTextAlignment(.trailing)
					Text("×")
					TextField("\(Nm(size.height).label)", text: $height)
						.frame(width: 64.0)
						.multilineTextAlignment(.trailing)
					Text("mm")
				}
				Picker("Layers", selection: Binding(get: { chosen }, set: { selected = $0 })) {
					ForEach(Stack.allCases, id: \.self) { stack in
						Text("\(stack.rawValue)").tag(stack)
					}
				}
				.pickerStyle(.segmented)

				if dropped > 0 {
					Text("Discards \(dropped) object\(dropped == 1 ? "" : "s")")
						.font(.caption)
						.foregroundStyle(.orange)
				}
			}
			.frame(width: 240.0)
		}
	}

	private func parse(_ text: String) -> Nm? {
		Double(text.replacingOccurrences(of: ",", with: ".")).map { value in .mm(value) }
	}
}
