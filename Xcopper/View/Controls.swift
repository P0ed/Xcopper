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

	var body: some View {
		Button(tool.actionName, systemImage: tool.systemImage, action: { state = tool })
			.foregroundStyle(state == tool ? Color.accentColor : .primary)
			.keyboardShortcut(KeyEquivalent(tool.shortcutCharacter), modifiers: [])
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
private struct Shortcut: ViewModifier {
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
