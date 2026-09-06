import SwiftUI

@MainActor
struct FootprintDialog: View {
	@Binding var spec: Footprint.Spec
	var confirm: () -> Void

	@State var draft: Footprint.Spec?

	private var current: Footprint.Spec { draft ?? spec }

	private var binding: Binding<Footprint.Spec> {
		Binding(get: { current }, set: { draft = $0 })
	}

	private var component: Binding<Component?> {
		Binding(
			get: { current.component },
			set: { component in
				draft = modifying(current) { $0.component = component }
			}
		)
	}

	private var device: Binding<Device> {
		Binding(get: { current.device }, set: { device in
			draft = modifying(current) { spec in
				spec.device = device
				if !device.packageKinds.contains(spec.kind), let kind = device.packageKinds.first {
					spec.kind = kind
				}
			}
		})
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
				PartPicker(component: component, onBoard: true)
				if let component = current.component {
					HStack {
						Text("Package")
							.foregroundStyle(.secondary)
						Text(component.packageName)
					}
				} else {
					Picker("Device", selection: device) {
						ForEach(Device.genericCases) { device in
							Text(device.name).tag(device)
						}
					}
					Picker("Package", selection: binding.kind) {
						ForEach(current.device.packageKinds) { kind in
							Text(kind.name).tag(kind)
						}
					}
					if current.kind.hasChip {
						Picker("Size", selection: binding.chip) {
							ForEach(Footprint.Chip.allCases) { chip in
								Text(chip.name).tag(chip)
							}
						}
					}
					if current.kind.hasPins {
						Stepper(
							"Pins: \(current.pins)",
							value: binding.pins,
							in: pinRange,
							step: pinStep
						)
					}
					if current.kind.hasRows {
						Picker("Rows", selection: binding.rows) {
							Text("1").tag(1)
							Text("2").tag(2)
						}
						.pickerStyle(.segmented)
					}
					HStack {
						Text("Symbol")
							.foregroundStyle(.secondary)
						Text(current.symbol.summary)
					}
				}
			}
			.frame(width: 240.0)
		}
	}

	private var pinRange: ClosedRange<Int> {
		switch current.kind {
		case .header: 1 ... 40
		default: 2 ... 64
		}
	}

	private var pinStep: Int {
		switch current.kind {
		case .header: 1
		default: 2
		}
	}
}
