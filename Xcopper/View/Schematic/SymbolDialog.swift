import SwiftUI

@MainActor
struct SymbolDialog: View {
	@Binding var spec: Symbol.Spec
	var confirm: () -> Void

	@State var draft: Symbol.Spec?

	private var current: Symbol.Spec { draft ?? spec }

	private var binding: Binding<Symbol.Spec> {
		Binding(get: { current }, set: { draft = $0 })
	}

	/// Changing kind carries the value over only when it still means something
	private var kind: Binding<Symbol.Kind> {
		Binding(
			get: { current.kind },
			set: { kind in
				draft = modifying(current) { spec in
					if spec.kind.isPower != kind.isPower { spec.value = kind.defaultValue }
					spec.kind = kind
				}
			}
		)
	}

	var body: some View {
		Dialog(
			action: "Place",
			confirm: {
				spec = current
				confirm()
			}
		) {
			VStack(alignment: .leading, spacing: 10.0) {
				Picker("Kind", selection: kind) {
					ForEach(Symbol.Kind.allCases) { kind in
						Text(kind.name).tag(kind)
					}
				}
				if current.kind.hasPins {
					Stepper("Pins: \(current.pins)", value: binding.pins, in: 2 ... 64)
				}
				HStack {
					Text(current.kind.isPower ? "Net" : "Value")
						.foregroundStyle(.secondary)
						.frame(width: 44.0, alignment: .leading)
					TextField(current.kind.defaultValue, text: binding.value)
				}
			}
			.frame(width: 240.0)
		}
	}
}
