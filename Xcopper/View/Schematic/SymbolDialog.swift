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
					Picker("Kind", selection: binding.kind) {
						ForEach(Symbol.Kind.allCases) { kind in
							Text(kind.name).tag(kind)
						}
					}
					if current.kind.hasPins {
						Stepper("Pins: \(current.pins)", value: binding.pins, in: 2 ... 64)
					}
				}
				HStack {
					Text("Package")
						.foregroundStyle(.secondary)
					Text(current.footprint.summary)
				}
				HStack {
					Text("Value")
						.foregroundStyle(.secondary)
						.frame(width: 44.0, alignment: .leading)
					TextField("", text: binding.value)
				}
			}
			.frame(width: 240.0)
		}
	}
}
