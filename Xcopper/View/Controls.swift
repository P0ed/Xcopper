import AppKit
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
struct ValuePicker<Value: Hashable>: View {
	var title: String
	@Binding var value: Value
	var options: [Value]
	var label: (Value) -> String

	var body: some View {
		PropertyRow(title: title) {
			Picker("", selection: $value) {
				ForEach(options, id: \.self) { option in
					Text("\(label(option))").tag(option)
				}
			}
			.labelsHidden()
		}
	}
}

extension ValuePicker where Value == µm {

	init(title: String, value: Binding<Value>, options: [Value]) {
		self.init(title: title, value: value, options: options, label: { "\($0.label) mm" })
	}
}

@MainActor
struct PropertyRow<Content: View>: View {
	var title: String
	@ViewBuilder var content: () -> Content

	var body: some View {
		HStack(spacing: 6.0) {
			Text(title)
				.foregroundStyle(.secondary)
				.frame(maxWidth: .infinity, alignment: .leading)
			content()
				.frame(maxWidth: .infinity, alignment: .trailing)
		}
	}
}

@MainActor
struct PropertyEditing: ViewModifier {
	var property: Property
	@FocusState.Binding var focus: Property?

	func body(content: Content) -> some View {
		content
			.focused($focus, equals: property)
			.onSubmit(finish)
			.onExitCommand(perform: finish)
	}

	private func finish() {
		let window = NSApp.keyWindow
		DispatchQueue.main.async {
			guard focus == property else { return }
			if let window, !window.makeFirstResponder(nil) { return }
			focus = nil
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
				.modifier(PropertyEditing(property: property, focus: $focus))
		}
	}
}

@MainActor
struct ToggleRow: View {
	var title: String
	var label: String
	@Binding var value: Bool

	var body: some View {
		PropertyRow(title: title) {
			Toggle(label, isOn: $value)
				.toggleStyle(.checkbox)
		}
	}
}

@MainActor
struct LengthRow: View {
	var title: String
	@Binding var value: µm?
	var unit: LengthUnit = .millimeters
	var property: Property
	@FocusState.Binding var focus: Property?

	private var length: Binding<Double?> {
		Binding(
			get: { value.map { Double($0) / Double(unit.scale) } },
			set: { typed in
				guard let typed else { return }
				let millimeters = typed * Double(unit.scale) / Double(µm.mm)
				let length = µm((millimeters * Double(µm.mm)).rounded())
				guard length != value else { return }
				value = length
			}
		)
	}

	var body: some View {
		PropertyRow(title: title) {
			TextField(value == nil ? "Mixed" : "", value: length, format: MixedNumber(decimals: unit == .millimeters ? 3 : 8))
				.textFieldStyle(.roundedBorder)
				.modifier(PropertyEditing(property: property, focus: $focus))
				.overlay(alignment: .trailing) { unitLabel }
		}
	}

	private var unitLabel: some View {
		Text(unit.label)
			.font(.caption)
			.foregroundStyle(.tertiary)
			.padding(.trailing, 5.0)
			.allowsHitTesting(false)
	}
}

@MainActor
struct PositionRows: View {
	@Binding var at: Point
	var unit: LengthUnit = .millimeters
	@FocusState.Binding var focus: Property?

	private var x: Binding<µm> {
		Binding(get: { at.x }, set: { at.x = Int($0) })
	}

	private var y: Binding<µm> {
		Binding(get: { at.y }, set: { at.y = Int($0) })
	}

	var body: some View {
		LengthRow(title: "X", value: Binding(x), unit: unit, property: .x, focus: $focus)
		LengthRow(title: "Y", value: Binding(y), unit: unit, property: .y, focus: $focus)
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

struct MixedNumber: ParseableFormatStyle {
	var decimals = 3
	var number: FloatingPointFormatStyle<Double> {
		.number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never).precision(.fractionLength(0 ... decimals))
	}

	var parseStrategy: Strategy { Strategy() }

	func format(_ value: Double?) -> String { value.map(number.format) ?? "" }

	struct Strategy: ParseStrategy {
		func parse(_ value: String) throws -> Double? {
			let text = value.trimmingWhitespace
			guard !text.isEmpty else { return nil }
			guard let number = Double(text), number.isFinite else {
				throw Err("Use a number with '.' as the decimal separator.")
			}
			return number
		}
	}
}

extension String {
	static func millimeters(_ value: Double, decimals: Int = 2) -> String {
		"\(String(format: "%.2f", value)) mm"
	}
	static func millimeters(_ value: µm, decimals: Int = 2) -> String {
		"\(mm(value, decimals: decimals)) mm"
	}
	static func mm(_ value: µm, decimals: Int = 6) -> String {
		String(format: "%.\(decimals)f", Double.mm(value))
	}
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
