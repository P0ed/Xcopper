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

	private var component: Binding<Component?> {
		Binding(
			get: { current.component },
			set: { component in
				draft = modifying(current) { spec in
					spec.component = component
					if let component {
						spec.kind = component.symbolKind
						spec.pins = component.pinNames.count
						spec.value = component.name
					}
				}
			}
		)
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
				PartPicker(component: component)
				if current.component == nil {
					Picker("Kind", selection: kind) {
						ForEach(Symbol.Kind.allCases) { kind in
							Text(kind.name).tag(kind)
						}
					}
					if current.kind.hasPins {
						Stepper("Pins: \(current.pins)", value: binding.pins, in: 2 ... 64)
					}
				}
				// The footprint that goes on the board with it, named before it does
				HStack {
					Text("Package")
						.foregroundStyle(.secondary)
					Text(current.footprint?.summary ?? "None")
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
