import SwiftUI

@MainActor
struct ModePicker: View {
	@Binding var mode: Mode

	var body: some View {
		ForEach(Mode.allCases, id: \.self) { candidate in
			Button(candidate.name, systemImage: candidate.systemImage) { mode = candidate }
				.foregroundStyle(mode == candidate ? Color.accentColor : .primary)
		}
	}
}

@MainActor
struct ToolButton<T: ToolKind>: View {
	var tool: T
	@Binding
	var state: T
	var shortcuts: Bool = true

	var body: some View {
		Button(tool.actionName, systemImage: tool.systemImage, action: { state = tool })
			.foregroundStyle(state == tool ? Color.accentColor : .primary)
			.modifier(Shortcut(shortcut: shortcuts ? tool.shortcutCharacter : nil, modifiers: []))
	}
}

@MainActor
struct CounterpartButton: View {
	var operations: Operations

	var body: some View {
		if operations.counterpartCount > 0 {
			Button(
				operations.counterpartName,
				systemImage: operations.counterpartImage,
				action: { operations.showCounterpart() }
			)
			.buttonStyle(.borderless)
			.padding(.top, 2.0)
		}
	}
}

@MainActor
struct PartPicker: View {
	@Binding var component: Component?
	/// The layout offers only the parts that also stand on the board
	var onBoard: Bool = false

	var body: some View {
		Picker("Part", selection: $component) {
			Text("Generic").tag(Component?.none)
			ForEach(Component.Category.allCases) { category in
				let shelf = onBoard ? category.layoutComponents : category.components
				if !shelf.isEmpty {
					Section(category.name) {
						ForEach(shelf) { part in
							Text(part.name).tag(Component?.some(part))
						}
					}
				}
			}
		}
	}
}

@MainActor
struct ActionButton: View {
	var name: String
	var image: String
	var shortcut: Character?
	var modifiers: EventModifiers = []
	var disabled: Bool = false
	var action: () -> Void

	var body: some View {
		Button(name, systemImage: image, action: action)
			.disabled(disabled)
			.modifier(Shortcut(shortcut: shortcut, modifiers: modifiers))
	}
}

@MainActor
struct Shortcut: ViewModifier {
	var shortcut: Character?
	var modifiers: EventModifiers

	func body(content: Content) -> some View {
		if let shortcut {
			content.keyboardShortcut(KeyEquivalent(shortcut), modifiers: modifiers)
		} else {
			content
		}
	}
}

@MainActor
struct NetRow: View {
	var name: String
	var color: Color
	var selected: Bool
	var select: () -> Void
	var remove: (() -> Void)?

	var body: some View {
		HStack(spacing: 6.0) {
			Circle().fill(color).frame(width: 10.0, height: 10.0)
			Text(name).lineLimit(1)
			Spacer(minLength: 0.0)
			if let remove {
				Button("Delete", systemImage: "xmark", action: remove)
					.buttonStyle(.borderless)
					.labelStyle(.iconOnly)
					.foregroundStyle(.tertiary)
			}
		}
		.padding(.horizontal, 6.0)
		.padding(.vertical, 3.0)
		.background(selected ? Color.accentColor.opacity(0.25) : .clear, in: .rect(cornerRadius: 5.0))
		.contentShape(.rect)
		.onTapGesture(perform: select)
	}
}

@MainActor
struct Panel<Content: View>: View {
	var title: String
	@ViewBuilder var content: () -> Content

	var body: some View {
		VStack(alignment: .leading, spacing: 4.0) {
			Text(title)
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
			content()
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}
}

@MainActor
struct GridPicker: View {
	var title: String
	@Binding var value: Nm
	var options: [Nm]

	var body: some View {
		PropertyRow(title: title) {
			Picker("", selection: $value) {
				ForEach(options, id: \.self) { option in
					Text("\(option.label) mm").tag(option)
				}
			}
			.labelsHidden()
		}
	}
}

enum Property: Hashable {
	case reference, value, text, x, y, width, drill, pad, diameter, clearance
}

extension CGFloat {
	static var captionWidth: CGFloat { 52.0 }
}

@MainActor
struct PropertyRow<Content: View>: View {
	var title: String
	@ViewBuilder var content: () -> Content

	var body: some View {
		HStack(spacing: 6.0) {
			Text(title)
				.foregroundStyle(.secondary)
				.frame(width: .captionWidth, alignment: .leading)
			content()
				.frame(maxWidth: .infinity, alignment: .leading)
		}
	}
}

@MainActor
struct TextRow: View {
	var title: String
	var prompt: String = ""
	@Binding var text: String
	var property: Property
	@FocusState.Binding var focus: Property?

	var body: some View {
		PropertyRow(title: title) {
			TextField(prompt, text: $text)
				.textFieldStyle(.roundedBorder)
				.focused($focus, equals: property)
		}
	}
}

@MainActor
struct LengthRow: View {
	var title: String
	@Binding var value: Nm
	var range: ClosedRange<Double> = 0.0 ... 2_000.0
	var property: Property
	@FocusState.Binding var focus: Property?

	private var millimeters: Binding<Double> {
		Binding(
			get: { value.mm },
			set: { typed in
				let length = Nm.mm(min(max(typed, range.lowerBound), range.upperBound))
				guard length != value else { return }
				value = length
			}
		)
	}

	var body: some View {
		PropertyRow(title: title) {
			TextField("", value: millimeters, format: .number.precision(.fractionLength(0 ... 3)))
				.textFieldStyle(.roundedBorder)
				.focused($focus, equals: property)
				.overlay(alignment: .trailing) { unit }
		}
	}

	private var unit: some View {
		Text("mm")
			.font(.caption)
			.foregroundStyle(.tertiary)
			.padding(.trailing, 5.0)
			.allowsHitTesting(false)
	}
}

@MainActor
struct PositionRows: View {
	@Binding var at: Pt
	@FocusState.Binding var focus: Property?

	private static let span: ClosedRange<Double> = -2_000.0 ... 2_000.0

	private var x: Binding<Nm> {
		Binding(get: { Nm(clamping: at.x) }, set: { at = Pt(x: Int($0), y: at.y) })
	}

	private var y: Binding<Nm> {
		Binding(get: { Nm(clamping: at.y) }, set: { at = Pt(x: at.x, y: Int($0)) })
	}

	var body: some View {
		LengthRow(title: "X", value: x, range: Self.span, property: .x, focus: $focus)
		LengthRow(title: "Y", value: y, range: Self.span, property: .y, focus: $focus)
	}
}

@MainActor
struct ChoiceRow<Value: Hashable, Content: View>: View {
	var title: String
	@Binding var value: Value
	@ViewBuilder var content: () -> Content

	var body: some View {
		PropertyRow(title: title) {
			Picker("", selection: $value) { content() }
				.labelsHidden()
		}
	}
}

func millimeters(_ value: Double) -> String {
	"\(String(format: "%.2f", value)) mm"
}

@MainActor
struct ValueRow: View {
	var title: String
	var value: String

	var body: some View {
		PropertyRow(title: title) {
			Text(value)
				.lineLimit(1)
		}
	}
}
