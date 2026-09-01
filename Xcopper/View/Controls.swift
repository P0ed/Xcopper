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
	/// Off while a sidebar field has the keyboard, so a tool letter typed into
	/// a value stays in it
	var shortcuts: Bool = true

	var body: some View {
		Button(tool.actionName, systemImage: tool.systemImage, action: { state = tool })
			.foregroundStyle(state == tool ? Color.accentColor : .primary)
			.modifier(Shortcut(shortcut: shortcuts ? tool.shortcutCharacter : nil, modifiers: []))
	}
}

/// Turns the document over to its other half, where the part picked here also
/// stands. Nothing but the shared designator pairs the two, so the button is
/// there only while the selection has a counterpart to show.
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
	var select: () -> Void = ø
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
	}
}

@MainActor
struct GridPicker: View {
	var title: String
	@Binding var value: Nm
	var options: [Nm]

	var body: some View {
		HStack(spacing: 6.0) {
			Text(title)
				.foregroundStyle(.secondary)
				.frame(width: 40.0, alignment: .leading)
			Picker("", selection: $value) {
				ForEach(options, id: \.self) { option in
					Text("\(option.label) mm").tag(option)
				}
			}
			.labelsHidden()
		}
	}
}

/// Which inspector field has the keyboard. Plain key shortcuts stand down
/// while one of them does, so a letter typed into a value cannot pick a tool
/// and a backspace cannot delete the very object being described.
enum Property: Hashable {
	case reference, value, text, x, y, width, drill, pad, diameter
}

/// One labeled row of the inspector
@MainActor
struct PropertyRow<Content: View>: View {
	var title: String
	@ViewBuilder var content: () -> Content

	var body: some View {
		HStack(spacing: 6.0) {
			Text(title)
				.foregroundStyle(.secondary)
				.frame(width: 52.0, alignment: .leading)
			content()
		}
	}
}

/// Text the document stores verbatim: a reference designator, a part value,
/// the name a label puts on its net
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

/// A length, shown in the millimeters the board is drawn in and stored in the
/// nanometers it is measured in
@MainActor
struct LengthRow: View {
	var title: String
	@Binding var value: Nm
	var range: ClosedRange<Double> = 0.0 ... 2_000.0
	var property: Property
	@FocusState.Binding var focus: Property?

	/// A formatted field writes its parsed value back as soon as it is drawn,
	/// so a write that changes nothing is dropped rather than left to mark the
	/// document edited for no more than looking at a selection
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
			Text("mm")
				.font(.caption)
				.foregroundStyle(.tertiary)
		}
	}
}

/// Where a one point object sits, the only geometry it has
@MainActor
struct PositionRows: View {
	@Binding var at: Pt
	@FocusState.Binding var focus: Property?

	/// Objects are allowed off the edge of the board, so a coordinate may be
	/// negative
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

/// A property picked from a short list, with no keyboard to stand down for
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

/// A length as the canvas readouts write it, so the sidebar and the drawing agree
func millimeters(_ value: Double) -> String {
	"\(String(format: "%.2f", value)) mm"
}

/// A property the drawing works out for itself, which is why it is not editable
@MainActor
struct ValueRow: View {
	var title: String
	var value: String

	var body: some View {
		PropertyRow(title: title) {
			Text(value)
				.lineLimit(1)
			Spacer(minLength: 0.0)
		}
	}
}
